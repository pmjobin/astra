#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compile real Astra COM providers and a separately declared Windows SDK client."""
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
	parser.add_argument('--cxx', required=True)
	parser.add_argument('--sysroot', type=Path)
	parser.add_argument('--output', type=Path, required=True)
	parser.add_argument('--iso', action='store_true')
	args = parser.parse_args()
	args.compiler = args.compiler.resolve()
	source = Path(__file__).resolve().parent
	root = source.parents[2]
	output = args.output.resolve()
	assert not output.is_relative_to(root)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='com-export-', dir=output))
	media = work / 'media'
	media.mkdir()
	identity = {'scope': 'actual Astra COM export and mixed C+COM; COM import NOT_TESTED; Windows execution required',
		'compiler_sha256': hashlib.sha256(args.compiler.read_bytes()).hexdigest(),
		'checks': [], 'sources': {}, 'products': {}}
	def save():
		(work / 'build.json').write_text(json.dumps(identity, indent=2) + '\n')
	def run(command, expected=0, contains=''):
		assert hashlib.sha256(args.compiler.read_bytes()).hexdigest() == identity['compiler_sha256'], 'compiler changed during product build'
		p = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=90,
			cwd=work, env=dict(os.environ, CCACHE_DISABLE='1'))
		identity['checks'].append({'command': list(map(str, command)), 'exit': p.returncode,
			'expected_exit': expected, 'stdout': p.stdout, 'stderr': p.stderr})
		save()
		assert p.returncode == expected and contains in p.stdout + p.stderr, identity['checks'][-1]
		return p.stdout
	target = ['--target=x86_64-w64-windows-gnu']
	identity['toolchain'] = run([args.cxx, '--version'])
	objdump = run([args.cxx, '-print-prog-name=objdump']).strip()
	flags = ['--sysroot=' + str(args.sysroot)] if args.sysroot else []
	for filename in ('counter.astra', 'client.cpp', 'support.cpp', 'run.cmd'):
		data = (source / filename).read_bytes()
		identity['sources'][filename] = hashlib.sha256(data).hexdigest()
		(media / filename).write_bytes(data)
	oracle = source.parent / 'com-host/allocation-oracle.hpp'
	(work / oracle.name).write_bytes(oracle.read_bytes())
	identity['sources'][oracle.name] = hashlib.sha256(oracle.read_bytes()).hexdigest()
	unit = media / 'counter.astra'
	generated = run([args.compiler, *target, '--emit-com-source', unit])
	adapter = work / 'adapter.cpp'
	adapter.write_text(generated)
	identity['sources']['generated-adapter.cpp'] = hashlib.sha256(adapter.read_bytes()).hexdigest()
	(work / 'com14.hpp').write_text(run([args.compiler, *target, '--emit-com-header', unit]))
	# C/C++ clients have declarations from their respective ABI authority only.
	run([args.cc, *flags, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic',
		'-c', root / 'lib/runtime/interop/foreign-14.c', '-o', work / 'foreign.o'])
	strict = ['-std=c++17', '-Wall', '-Wextra', '-Werror', '-pedantic', '-fno-exceptions', '-fno-rtti']
	header_check = work / 'header-check.cpp'
	header_check.write_text('#include "com14.hpp"\n#include "com14.hpp"\n')
	run([args.cxx, *flags, *strict, '-fsyntax-only', header_check])
	run([args.cxx, *flags, *strict, '-O2', '-static', '-Wl,--no-insert-timestamp',
		media / 'client.cpp', '-lole32', '-luuid', '-o', media / 'com-client.exe'])
	exports = ['create', 'acquire', 'release', 'get', 'set', 'root_identity', 'weak', 'weak_clone', 'weak_upgrade', 'weak_release', 'native_only']
	definition = work / 'com14.def'
	definition.write_text('EXPORTS\n' + ''.join('\tcom14_' + name + '\n' for name in exports))
	for level in ('0', '1', '2'):
		obj = work / ('native-O' + level + '.o')
		run([args.compiler, *target, '-O' + level, '-c', unit, '-o', obj])
		binary = media / ('com-provider-O' + level + '.dll')
		run([args.cxx, *flags, *strict, '-O' + level, '-I', work, '-shared', '-static', '-Wl,--no-insert-timestamp',
			adapter, media / 'support.cpp', obj, work / 'foreign.o', definition, '-lole32', '-luuid', '-o', binary])
	for binary in sorted(media.glob('*.dll')) + [media / 'com-client.exe']:
		identity['products'][binary.name] = hashlib.sha256(binary.read_bytes()).hexdigest()
		imports = run([objdump, '-p', binary])
		dependencies = [line.split(':', 1)[1].strip().lower() for line in imports.splitlines() if 'DLL Name:' in line]
		assert dependencies and set(dependencies) <= {'kernel32.dll', 'msvcrt.dll', 'ole32.dll'}, dependencies
		identity.setdefault('system_dll_dependencies', {})[binary.name] = dependencies
	healthy = unit.read_text()
	bad = work / 'invalid.astra'
	for text, reason in [
		(healthy.replace('849ad154-8d1e-4c63-9ea2-14329b022002', '849ad154-8d1e-4c63-9ea2-14329b022001'), 'two distinct explicit application GUIDs'),
		(healthy.replace('849ad154-8d1e-4c63-9ea2-14329b022001', '00000000-0000-0000-c000-000000000046'), 'two distinct explicit application GUIDs'),
		(healthy.replace('threading="constructing"', 'threading="agile"'), 'threading=constructing'),
		(healthy.replace('[Shared]', '[Shared,Monitor]'), 'plain Shared root'),
		(healthy.replace('[CExport(name="com14", property="value")]', ''), 'explicit Class CExport bridge'),
	]:
		bad.write_text(text)
		run([args.compiler, *target, '--check', bad], expected=1, contains=reason)
	run([args.compiler, '--check', unit], expected=1, contains='requires --target=x86_64-w64-windows-gnu')
	for stage in ('syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi'):
		run([args.compiler, *target, '--dump-' + stage, unit], contains='COMExport')
	run([args.compiler, *target, '--check', unit])
	(media / 'IDENTITY.json').write_text(json.dumps(identity, indent=2) + '\n')
	if args.iso:
		run(['genisoimage', '-quiet', '-J', '-R', '-V', 'ASTRA14_COM', '-o', work / 'com-export.iso', media])
		identity['iso_sha256'] = hashlib.sha256((work / 'com-export.iso').read_bytes()).hexdigest()
	identity['build_status'] = 'PASS; actual native Windows execution pending'
	save()
	print(work)


if __name__ == '__main__':
	main()
