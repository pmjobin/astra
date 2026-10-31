#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build distinct A123/A124/A125 applications; native Windows execution required."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--compiler', type=Path, required=True)
	parser.add_argument('--cc', required=True)
	parser.add_argument('--cxx', required=True)
	parser.add_argument('--sysroot', type=Path)
	parser.add_argument('--output', type=Path, required=True)
	parser.add_argument('--iso', action='store_true')
	args = parser.parse_args()
	compiler, output = args.compiler.resolve(), args.output.resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='windows-applications-', dir=output))
	media = work / 'media'
	media.mkdir()
	sources = ROOT / 'examples/interop-tooling-14/windows'
	receipt = {'scope': 'A123 reconciliation, A124 thermostat, A125 C+COM lease budget; Windows execution required',
		'compiler_sha256': sha(compiler), 'sources': {}, 'checks': [], 'products': {}, 'applications': {}}
	def save():
		(work / 'build.json').write_text(json.dumps(receipt, indent=2) + '\n')
	def run(command, contains=''):
		assert sha(compiler) == receipt['compiler_sha256'], 'compiler changed during build'
		p = subprocess.run(list(map(str, command)), cwd=work, capture_output=True, text=True, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1'))
		receipt['checks'].append({'command': list(map(str, command)), 'exit': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr})
		save()
		assert p.returncode == 0 and contains in p.stdout + p.stderr, receipt['checks'][-1]
		return p.stdout
	for path in sorted(sources.iterdir()):
		if path.is_file():
			shutil.copyfile(path, work / path.name)
			receipt['sources'][path.name] = sha(path)
	for path in [ROOT / 'tests/interop-tooling-14/com-host/allocation-oracle.hpp', ROOT / 'tests/interop-tooling-14/com-import/provider.cpp']:
		shutil.copyfile(path, work / path.name)
		receipt['sources'][str(path.relative_to(ROOT))] = sha(path)
	receipt['toolchain'] = run([args.cxx, '--version'])
	objdump = run([args.cxx, '-print-prog-name=objdump']).strip()
	flags = ['--sysroot=' + str(args.sysroot)] if args.sysroot else []
	strict = ['-std=c++17', '-Wall', '-Wextra', '-Werror', '-pedantic', '-fno-exceptions', '-fno-rtti']
	target = ['--target=x86_64-w64-windows-gnu']
	run([args.cc, *flags, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-c',
		ROOT / 'lib/runtime/interop/foreign-14.c', '-o', work / 'foreign.o'])
	run([args.cxx, *flags, *strict, '-O2', '-shared', '-static', '-Wl,--no-insert-timestamp',
		work / 'provider.cpp', '-lole32', '-luuid', '-o', media / 'a123-provider.dll'])
	for app, filename in [('A123', 'a123-reconciler.astra'), ('A124', 'a124-thermostat.astra'), ('A125', 'a125-lease-budget.astra')]:
		unit = work / filename
		adapter = work / (app + '-adapter.cpp')
		adapter.write_text(run([compiler, *target, '--emit-com-source', unit]))
		receipt['sources'][adapter.name] = sha(adapter)
		run([args.cxx, *flags, *strict, '-O2', '-c', adapter, '-o', work / (app + '-adapter.o')])
		# Clients use only independently authored SDK/C declarations and compile separately.
		client = work / (app.lower() + '-client.cpp')
		run([args.cxx, *flags, *strict, '-O2', '-c', client, '-o', work / (app + '-client.o')])
		if app != 'A123':
			run([args.cxx, *flags, *strict, '-O2', '-static', '-Wl,--no-insert-timestamp', work / (app + '-client.o'),
				'-lole32', '-luuid', '-o', media / (app.lower() + '-client.exe')])
		variants = []
		for level in ('0', '1', '2'):
			obj = work / (app + '-O' + level + '.o')
			run([compiler, *target, '-O' + level, '-c', unit, '-o', obj])
			base = [args.cxx, *flags, *strict, '-O2', '-static', '-Wl,--no-insert-timestamp',
				obj, work / (app + '-adapter.o'), work / 'foreign.o']
			if app == 'A123':
				binary = media / ('a123-O' + level + '.exe')
				run([*base, work / (app + '-client.o'), '-lole32', '-luuid', '-o', binary])
			else:
				binary = media / (app.lower() + '-O' + level + '.dll')
				definition = []
				if app == 'A125':
					def_file = work / 'a125.def'
					def_file.write_text('EXPORTS\n' + ''.join('\ta125_budget_' + name + '\n' for name in
						('create', 'acquire', 'release', 'get', 'set', 'root_identity', 'weak', 'weak_upgrade', 'weak_release')))
					definition = [def_file]
				run([*base, '-shared', work / (app.lower() + '-support.cpp'), *definition, '-lole32', '-luuid', '-o', binary])
			variants.append({'optimization': level, 'product': binary.name, 'sha256': sha(binary)})
		receipt['applications'][app] = {'source_sha256': sha(unit), 'client_sha256': sha(client), 'variants': variants,
			'status': 'BUILD_ONLY; Windows execution pending'}
	for binary in sorted(media.glob('*.exe')) + sorted(media.glob('*.dll')):
		receipt['products'][binary.name] = sha(binary)
		imports = run([objdump, '-p', binary])
		dependencies = [line.split(':', 1)[1].strip().lower() for line in imports.splitlines() if 'DLL Name:' in line]
		assert dependencies and set(dependencies) <= {'kernel32.dll', 'msvcrt.dll', 'ole32.dll'}, dependencies
		receipt.setdefault('system_dll_dependencies', {})[binary.name] = dependencies
	shutil.copyfile(work / 'run.cmd', media / 'run.cmd')
	(media / 'IDENTITY.json').write_text(json.dumps(receipt, indent=2) + '\n')
	if args.iso:
		run(['genisoimage', '-quiet', '-J', '-R', '-V', 'ASTRA14_APPS', '-o', work / 'windows-applications.iso', media])
		receipt['iso_sha256'] = sha(work / 'windows-applications.iso')
	receipt['status'] = 'BUILD_ONLY; actual native Windows execution pending'
	save()
	print(work)


if __name__ == '__main__':
	main()
