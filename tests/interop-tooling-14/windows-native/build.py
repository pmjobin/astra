#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build actual Astra Windows objects and independent native C clients."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import tempfile


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--compiler', type=Path, required=True)
	parser.add_argument('--cc', required=True)
	parser.add_argument('--sysroot', type=Path)
	parser.add_argument('--output', type=Path, required=True)
	parser.add_argument('--iso', action='store_true')
	args = parser.parse_args()
	source = Path(__file__).resolve().parent
	output = args.output.resolve()
	assert not output.is_relative_to(source.parents[2])
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='windows-native-', dir=output))
	media = work / 'media'
	media.mkdir()
	identity = {'scope': 'actual Astra Windows word/pointer C ABI and native Shared/Weak; COM adapters NOT_TESTED',
		'compiler_sha256': hashlib.sha256(args.compiler.read_bytes()).hexdigest(),
		'checks': [], 'sources': {}, 'products': {}}
	def save():
		(work / 'build.json').write_text(json.dumps(identity, indent=2) + '\n')
	def run(command, expected=0, contains=''):
		p = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=90,
			cwd=work, env=dict(os.environ, CCACHE_DISABLE='1'))
		identity['checks'].append({'command': list(map(str, command)), 'exit': p.returncode,
			'expected_exit': expected, 'stdout': p.stdout, 'stderr': p.stderr})
		save()
		assert p.returncode == expected and contains in p.stdout + p.stderr, identity['checks'][-1]
		return p.stdout
	target = ['--target=x86_64-w64-windows-gnu']
	run([args.compiler, *target, '--target-info'], contains='windows-interop-object-v1')
	identity['toolchain'] = run([args.cc, '--version'])
	objdump = run([args.cc, '-print-prog-name=objdump']).strip()
	flags = ['--sysroot=' + str(args.sysroot)] if args.sysroot else []
	for filename in ('lifetime.astra', 'client.c', 'run.cmd'):
		data = (source / filename).read_bytes()
		identity['sources'][filename] = hashlib.sha256(data).hexdigest()
		(media / filename).write_bytes(data)
	for level in ('0', '1', '2'):
		obj = work / ('native-O' + level + '.o')
		run([args.compiler, *target, '-O' + level, '-c', media / 'lifetime.astra', '-o', obj])
		binary = media / ('native-O' + level + '.exe')
		run([args.cc, *flags, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-static', '-Wl,--no-insert-timestamp',
			'-DASTRA_OPT=' + level, media / 'client.c', obj, '-o', binary])
		identity['products'][binary.name] = hashlib.sha256(binary.read_bytes()).hexdigest()
		imports = run([objdump, '-p', binary])
		dependencies = [line.split(':', 1)[1].strip().lower() for line in imports.splitlines() if 'DLL Name:' in line]
		assert dependencies and set(dependencies) <= {'kernel32.dll', 'msvcrt.dll'}, dependencies
		identity.setdefault('system_dll_dependencies', {})[binary.name] = dependencies
	bad = work / 'invalid.astra'
	for text in ['[CExport] f64 f(f64 x) { return x; }',
		'[Shared,Monitor] class T { init() {} }', 'class T { init() {} }',
		'[CExport] i64 f(i64 x) { return x; }', 'struct T { int n; }',
		'int f() { string text = "unsupported"; return 0; }']:
		bad.write_text(text)
		run([args.compiler, *target, '--check', bad], expected=1, contains='Windows interop object profile')
	run([args.compiler, *target, media / 'lifetime.astra', '-o', work / 'implicit.exe'], expected=2,
		contains='link the object with an explicit Windows toolchain')
	assert not (work / 'implicit.exe').exists()
	run([args.compiler, *target, '--runtime=none', '-c', media / 'lifetime.astra', '-o', work / 'none.o'], expected=2)
	assert not (work / 'none.o').exists()
	# A healthy control follows all refusal cases.
	run([args.compiler, *target, '--check', media / 'lifetime.astra'])
	(media / 'IDENTITY.json').write_text(json.dumps(identity, indent=2) + '\n')
	if args.iso:
		run(['genisoimage', '-quiet', '-J', '-R', '-V', 'ASTRA14_NATIVE', '-o', work / 'native-profile.iso', media])
		identity['iso_sha256'] = hashlib.sha256((work / 'native-profile.iso').read_bytes()).hexdigest()
	identity['build_status'] = 'PASS; native Windows execution required separately'
	save()
	print(work)


if __name__ == '__main__':
	main()
