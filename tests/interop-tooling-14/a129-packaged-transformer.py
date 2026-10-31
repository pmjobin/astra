#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""A129: an independent runtime file transformer from relocated versioned packages."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
LIBRARIES = ['base/errors.astra', 'hosted/text.astra', 'hosted/text-ops.astra', 'hosted/files.astra',
	'text/utf8-message.astra', 'text/utf8-byte-builder.astra', 'text/scalar-format.astra', 'collections/bag.astra']


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def oracle(data):
	runs, counts = [], [0, 0, 0]
	for line in data.split(b'\n'):
		if line.endswith(b'\r'):
			line = line[:-1]
		if not line:
			continue
		level, payload = line[0] - 48, line[2:]
		counts[level] += 1
		if runs and runs[-1][:2] == [level, payload]:
			runs[-1][2] += 1
		else:
			runs.append([level, payload, 1])
	return b''.join(str(count).encode() + b' ' + [b'info', b'warning', b'error'][level] + b': ' + payload + b'\n'
		for level, payload, count in runs) + b'counts ' + b' '.join(str(n).encode() for n in counts) + b'\n'


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path)
	parser.add_argument('output', type=Path)
	parser.add_argument('--prefix', type=Path, help='installed compiler/tool/library/example prefix for release qualification')
	args = parser.parse_args()
	compiler, output = args.compiler.resolve(), args.output.resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='a129-', dir=output))
	installed = args.prefix.resolve() if args.prefix else None
	if installed:
		assert compiler == installed / 'bin/astrac'
	lib = installed / 'share/astra' if installed else ROOT / 'lib/astra'
	sources = installed / 'share/astra/examples/interop-tooling-14/a129' if installed else ROOT / 'examples/interop-tooling-14/a129'
	tool = installed / 'bin/astra-pkg' if installed else ROOT / 'tools/packages/astra-pkg.py'
	rows = []
	receipt = {'application': 'A129', 'compiler_sha256': sha(compiler), 'tool_sha256': sha(tool),
		'mode': 'installed-prefix' if installed else 'development; final installed release still required', 'checks': rows,
		'sources': {p.name: sha(p) for p in sources.iterdir() if p.is_file()}}
	def run(command, *, expected=0, contains=''):
		assert sha(compiler) == receipt['compiler_sha256'], 'compiler changed during qualification'
		p = subprocess.run(list(map(str, command)), cwd=work, capture_output=True, text=True, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		rows.append({'command': list(map(str, command)), 'exit': p.returncode, 'expected_exit': expected, 'stdout': p.stdout, 'stderr': p.stderr})
		(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
		assert p.returncode == expected and contains in p.stdout + p.stderr, rows[-1]
		return p.stdout
	version = run([compiler, '--version']).split()[1]
	producer = work / 'producer'
	producer.mkdir()
	def package(name, version, files, deps=None, objects=None):
		path = producer / name
		path.mkdir()
		for target, source in files.items():
			dest = path / target
			dest.parent.mkdir(parents=True, exist_ok=True)
			shutil.copyfile(source, dest)
		data = {'format': 'astra-package/1', 'name': name, 'version': version, 'compiler': compiler_version,
			'abi': 'source+native-unit/1', 'license': 'Apache-2.0 WITH LLVM-exception',
			'sources': list(files), 'dependencies': deps or {}, **({'objects': objects} if objects else {})}
		(path / 'astra-package.json').write_text(json.dumps(data, indent=2) + '\n')
		return path
	compiler_version = version
	foundation = package('foundation14', '0.4.0', {name: lib / name for name in LIBRARIES}, objects=[name + '.o' for name in ('args', 'text', 'text-ops', 'files')])
	for name in ('args', 'text', 'text-ops', 'files'):
		run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-c',
			lib / ('platform/' + name + '-posix.c'), '-o', foundation / (name + '.o')])
	records = package('records14', '0.2.1', {'records.astra': sources / 'records.astra'}, {'foundation14': '0.4.0'})
	transformer = package('transform14', '0.9.0', {'transformer.astra': sources / 'transformer.astra'}, {'records14': '0.2.1'})
	package_prefix = work / 'package-install'
	def pkg(command, package, *, paths=(), extra=(), expected=0, contains=''):
		return run([sys.executable, tool, command, '--compiler', compiler, '--prefix', package_prefix, '--package', package,
			*[item for path in paths for item in ('--path', path)], *extra], expected=expected, contains=contains)
	pkg('lock', transformer, paths=[foundation, records])
	pkg('install', transformer, paths=[foundation, records])
	producer.rename(work / 'producer-withheld')
	assert not producer.exists()
	consumer = work / 'independent-consumer'
	consumer.mkdir()
	shutil.copyfile(sources / 'main.astra', consumer / 'main.astra')
	manifest = {'format': 'astra-package/1', 'name': 'diagnostic14', 'version': '0.1.0', 'compiler': version,
		'abi': 'source+native-unit/1', 'license': 'Apache-2.0 WITH LLVM-exception', 'sources': ['main.astra'],
		'dependencies': {'transform14': '0.9.0'}}
	(consumer / 'astra-package.json').write_text(json.dumps(manifest, indent=2) + '\n')
	pkg('lock', consumer)
	lock = (consumer / 'astra-package.lock').read_bytes()
	assert str(work).encode() not in lock
	assert {p['name'] for p in json.loads(lock)['packages']} == {'foundation14', 'records14', 'transform14', 'diagnostic14'}
	relocated = work / 'relocated-packages'
	package_prefix.rename(relocated)
	package_prefix = relocated
	pkg('list', consumer, contains='transform14@0.9.0')
	assert (consumer / 'astra-package.lock').read_bytes() == lock
	data = '1|café\n1|café\r\n2|bad\x00field\n0|ready 🖤\n0|ready 🖤\n1|café'.encode()
	rng = random.Random(129)
	random_data = b'\n'.join(str(rng.randrange(3)).encode() + b'|' + rng.choice([b'alpha', 'é'.encode(), b'', b'nul\0tail']) for _ in range(96)) + b'\n'
	fixtures = [('unicode-nul-crlf', data, 0), ('empty', b'', 0), ('runs', b'2|bad\n' * 64, 0),
		('random-records', random_data, 0), ('bad-level', b'3|bad\n', 3), ('missing-separator', b'1bad\n', 3), ('invalid-utf8', b'0|\xff\n', 3)]
	for name, content, _ in fixtures:
		(work / (name + '.input')).write_bytes(content)
	for level in ('0', '1', '2'):
		binary = work / ('transform-O' + level)
		pkg('build', consumer, extra=['-O', level, '-o', binary])
		for name, content, status in fixtures:
			target = work / (name + '-O' + level + '.output')
			run([binary, work / (name + '.input'), target], expected=status)
			if status == 0:
				assert target.read_bytes() == oracle(content), name
			else:
				assert not target.exists(), name
			if level in ('0', '2') and name in ('unicode-nul-crlf', 'invalid-utf8', 'bad-level'):
				memory_target = work / (name + '-vg-O' + level + '.output')
				run(['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full', '--errors-for-leak-kinds=all',
					'--error-exitcode=99', binary, work / (name + '.input'), memory_target], expected=status, contains='ERROR SUMMARY: 0 errors')
				if status == 0:
					assert memory_target.read_bytes() == oracle(content)
		run([binary], expected=64)
		run([binary, work / 'absent.input', work / ('missing-O' + level)], expected=2)
		run([binary, work / 'empty.input', work / 'absent-directory/output'], expected=2)
		deps = run(['readelf', '-d', binary])
		assert not any(name in deps for name in ('libgobject', 'libglib', 'libLLVM', 'liburing'))
		receipt.setdefault('variants', []).append({'optimization': level, 'binary_sha256': sha(binary)})
	tampered = package_prefix / 'share/astra/packages/records14/0.2.1/records.astra'
	healthy = tampered.read_bytes()
	tampered.write_bytes(healthy + b'// changed\n')
	pkg('build', consumer, extra=['-O', '2', '-o', work / 'tampered'], expected=1, contains='integrity')
	assert not (work / 'tampered').exists()
	tampered.write_bytes(healthy)
	pkg('build', consumer, extra=['-O', '2', '-o', work / 'restored'])
	run([work / 'restored', work / 'runs.input', work / 'restored.output'])
	assert (work / 'restored.output').read_bytes() == oracle(b'2|bad\n' * 64)
	assert (consumer / 'astra-package.lock').read_bytes() == lock
	receipt['lock_sha256'] = hashlib.sha256(lock).hexdigest()
	receipt['packages'] = json.loads(lock)['packages']
	receipt['status'] = 'PASS'
	(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	print(f'PASS: A129 versioned installed transitive packages, offline relocated lock, real UTF8/NUL files and cleanup; {len(rows)} commands; evidence {work}')


if __name__ == '__main__':
	main()
