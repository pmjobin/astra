#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent projects exercise package installs, public codegen and refusals."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main(compiler_arg, output_arg):
	compiler = Path(compiler_arg).resolve()
	output = Path(output_arg).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='packages-', dir=output))
	tool = ROOT / 'tools/packages/astra-pkg.py'
	rows = []
	receipt = {'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
		'tool_sha256': hashlib.sha256(tool.read_bytes()).hexdigest(), 'checks': rows}

	def run(args, expect=0, contains=''):
		p = subprocess.run(list(map(str, args)), cwd=work, capture_output=True, text=True,
			timeout=90, env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1',
			PATH=str(compiler.parent) + os.pathsep + os.environ['PATH']))
		rows.append({'command': list(map(str, args)), 'expected_exit': expect,
			'exit': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr})
		(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
		assert p.returncode == expect and contains in p.stdout + p.stderr, rows[-1]
		return p.stdout

	version = run([compiler, '--version']).split()[1]
	run([sys.executable, tool, 'create', work / 'created', '--name', 'created',
		'--compiler-version', version, '--license', 'Apache-2.0 WITH LLVM-exception'])
	assert json.loads((work / 'created/astra-package.json').read_text())['name'] == 'created'
	def package(name, source, deps=None, **extra):
		root = work / name
		root.mkdir()
		(root / 'source.astra').write_text(source)
		data = {'format': 'astra-package/1', 'name': name, 'version': '0.1.0',
			'compiler': version, 'abi': 'source+native-unit/1', 'license': 'Apache-2.0 WITH LLVM-exception',
			'sources': ['source.astra'], 'dependencies': deps or {}, **extra}
		(root / 'astra-package.json').write_text(json.dumps(data, indent=2) + '\n')
		return root, data

	math, math_data = package('math', 'namespace Math14;\npublic T identity<T>(T value) { return value; }\n')
	foreign, foreign_data = package('foreign', 'namespace Foreign14;\nusing Math14;\n'
		'extern(C) int package_increment(int value);\npublic int adjust(int value) { return package_increment(identity<int>(value)); }\n',
		{'math': '0.1.0'}, objects=['provider.o'])
	(foreign / 'provider.c').write_text('#include <stdint.h>\nint32_t package_increment(int32_t x) { return x + 2; }\n')
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', foreign / 'provider.c', '-o', foreign / 'provider.o'])
	app, app_data = package('app', 'using Foreign14;\nint main() { return adjust(40) - 42; }\n', {'foreign': '0.1.0'})
	prefix = work / 'prefix'
	def pkg(command, root, paths=(), prefix_path=prefix, extra=(), expect=0, contains=''):
		args = [sys.executable, tool, command, '--package', root, '--compiler', compiler, '--prefix', prefix_path]
		for path in paths:
			args += ['--path', path]
		return run(args + list(extra), expect, contains)

	pkg('lock', foreign, [math])
	pkg('install', foreign, [math])
	pkg('install', foreign, [math])
	# A consumer has only installed dependencies. No producer source tree is needed.
	shutil.rmtree(math)
	shutil.rmtree(foreign)
	pkg('lock', app)
	pkg('list', app, contains='math@0.1.0')
	run([sys.executable, tool, 'list', '--package', app, '--prefix', prefix, '--compiler', compiler.name], contains='math@0.1.0')
	for level in ('0', '1', '2'):
		product = work / ('app-O' + level)
		pkg('build', app, extra=['-O', level, '-o', product])
		run([product])
		# Locks contain no absolute paths and survive moving the full installation.
	assert str(work) not in (app / 'astra-package.lock').read_text()
	relocated = work / 'relocated'
	prefix.rename(relocated)
	pkg('build', app, prefix_path=relocated, extra=['-O', '2', '-o', work / 'relocated-app'])
	run([work / 'relocated-app'])
	pkg('build', app, prefix_path=relocated, extra=['-o', work / 'relocated-app'], expect=1, contains='already exists')
	installed_math = relocated / 'share/astra/packages/math/0.1.0/source.astra'
	healthy = installed_math.read_bytes()
	installed_math.write_bytes(healthy + b'// tampered\n')
	pkg('build', app, prefix_path=relocated, extra=['-o', work / 'tampered'], expect=1, contains='integrity')
	assert not (work / 'tampered').exists()
	installed_math.write_bytes(healthy)
	(app / 'astra-package.json').write_text(json.dumps({**app_data, 'dependencies': {'foreign': '0.2.0'}}))
	pkg('lock', app, prefix_path=relocated, expect=1)
	(app / 'astra-package.json').write_text(json.dumps(app_data, indent=2) + '\n')
	# A separately compiled native package preserves the existing exact compiler ABI.
	native, native_data = package('native', 'namespace Native14;\npublic int twice(int value) { return value * 2; }\n')
	run([compiler, '-O2', '-c', '--module', 'Native14', '--emit-interface', native / 'provider.asti',
		'--native-export', 'Native14.twice', native / 'source.astra', '-o', native / 'provider.o'])
	native_data.update(sources=[], native_modules=['provider.asti'], assets=['provider.o'])
	(native / 'astra-package.json').write_text(json.dumps(native_data, indent=2) + '\n')
	pkg('lock', native, prefix_path=relocated)
	pkg('install', native, prefix_path=relocated)
	shutil.rmtree(native)
	native_app, _ = package('native-app', 'using Native14;\nint main() { return twice(21) - 42; }\n', {'native': '0.1.0'})
	pkg('lock', native_app, prefix_path=relocated)
	pkg('build', native_app, prefix_path=relocated, extra=['-O', '2', '-o', work / 'native-app-bin'])
	run([work / 'native-app-bin'])
	# Independent invalid manifests/graphs fail before the compiler can emit output.
	one, one_data = package('one', 'int one() { return 1; }\n', {'two': '0.1.0'})
	two, two_data = package('two', 'int two() { return 2; }\n', {'one': '0.1.0'})
	pkg('lock', one, [two], expect=1, contains='cycle')
	(one / 'astra-package.json').write_text(json.dumps({**one_data, 'dependencies': {}}))
	pkg('lock', one, [two, two], expect=1, contains='duplicate package')
	for field, value, reason in [('sources', ['../outside.astra'], 'unsafe'), ('compiler', '999.0.0', 'incompatible'),
		('version', '01.0.0', 'invalid'), ('abi', 'invented/1', 'unsupported'), ('sources', ['source.astra', 'source.astra'], 'duplicate')]:
		(one / 'astra-package.json').write_text(json.dumps({**one_data, 'dependencies': {}, field: value}))
		pkg('lock', one, expect=1, contains=reason)
	(one / 'astra-package.json').write_text(json.dumps({**one_data, 'dependencies': {}}))
	link = work / 'symlink-package'
	link.symlink_to(one, target_is_directory=True)
	pkg('lock', link, expect=1, contains='symlink')
	(one / 'source.astra').unlink()
	(one / 'source.astra').symlink_to(two / 'source.astra')
	pkg('lock', one, expect=1, contains='symlink')
	(one / 'astra-package.json').write_text('{"format":"astra-package/1","format":"duplicate"}')
	pkg('lock', one, expect=1, contains='duplicate JSON')
	# Restore installed data and execute another healthy build after negative controls.
	pkg('build', app, prefix_path=relocated, extra=['-O', '2', '-o', work / 'restored'])
	run([work / 'restored'])
	receipt['status'] = 'PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print(f'PASS: {len(rows)} package/compiler/client commands; evidence {work}')


if __name__ == '__main__':
	main(*sys.argv[1:])
