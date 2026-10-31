#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build independent Windows COM host-probe products and optional read-only ISO."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--cxx', required=True)
	parser.add_argument('--sysroot', type=Path)
	parser.add_argument('--output', type=Path, required=True)
	parser.add_argument('--iso', action='store_true')
	args = parser.parse_args()
	source = Path(__file__).resolve().parent
	root = source.parents[2]
	output = args.output.resolve()
	assert not output.is_relative_to(root)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='host-', dir=output))
	media = work / 'media'
	media.mkdir()
	rows = []
	identity = {'scope': 'independent C++ Windows host capability probe; Astra COM code is not tested',
		'checks': rows, 'sources': {}, 'products': {}}
	def run(command):
		p = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=90)
		rows.append({'command': list(map(str, command)), 'exit': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr})
		(work / 'build.json').write_text(json.dumps(identity, indent=2) + '\n')
		assert p.returncode == 0, rows[-1]
		return p.stdout
	identity['toolchain'] = run([args.cxx, '--version'])
	objdump = run([args.cxx, '-print-prog-name=objdump']).strip()
	flags = ['--sysroot=' + str(args.sysroot)] if args.sysroot else []
	for filename in ('interfaces.hpp', 'provider.cpp', 'client.cpp', 'run.cmd'):
		data = (source / filename).read_bytes()
		identity['sources'][filename] = hashlib.sha256(data).hexdigest()
		(media / filename).write_bytes(data)
	for filename, product, extra in [('provider.cpp', 'host-provider.dll', ['-shared']), ('client.cpp', 'host-client.exe', [])]:
		run([args.cxx, *flags, '-std=c++17', '-O2', '-Wall', '-Werror', '-static',
			*extra, media / filename, '-lole32', '-luuid', '-o', media / product])
		identity['products'][product] = hashlib.sha256((media / product).read_bytes()).hexdigest()
		imports = run([objdump, '-p', media / product])
		dependencies = [line.split(':', 1)[1].strip().lower() for line in imports.splitlines() if 'DLL Name:' in line]
		assert dependencies and set(dependencies) <= {'kernel32.dll', 'msvcrt.dll', 'ole32.dll'}, dependencies
		identity.setdefault('system_dll_dependencies', {})[product] = dependencies
	(media / 'IDENTITY.json').write_text(json.dumps(identity, indent=2) + '\n')
	if args.iso:
		run(['genisoimage', '-quiet', '-J', '-R', '-V', 'ASTRA14_HOST', '-o', work / 'host-probe.iso', media])
		identity['iso_sha256'] = hashlib.sha256((work / 'host-probe.iso').read_bytes()).hexdigest()
	(work / 'build.json').write_text(json.dumps(identity, indent=2) + '\n')
	print(work)


if __name__ == '__main__':
	main()
