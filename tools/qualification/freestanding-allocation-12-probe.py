# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Read-only local target discovery; never boots a guest or installs tools."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import platform
import shutil
import subprocess
import time


ROOT = Path(__file__).resolve().parents[2]


def identity(path):
	path = Path(path).resolve(strict=True)
	digest = hashlib.sha256()
	with path.open('rb') as stream:
		for block in iter(lambda: stream.read(1024 * 1024), b''):
			digest.update(block)
	return dict(path=str(path), bytes=path.stat().st_size, sha256=digest.hexdigest())


def invoke(arguments):
	start = time.monotonic()
	try:
		result = subprocess.run(arguments, capture_output=True, text=True,
			timeout=15, cwd=ROOT, env=dict(os.environ, LC_ALL='C'))
		return dict(argv=arguments, exit=result.returncode,
			seconds=time.monotonic() - start, stdout=result.stdout,
			stderr=result.stderr)
	except (OSError, subprocess.TimeoutExpired) as error:
		return dict(argv=arguments, error=str(error), seconds=time.monotonic() - start)


def probe():
	result = dict(format='astra-local-target-probe/1',
		created_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
		host=platform.uname()._asdict(),
		os_release=Path('/etc/os-release').read_text(),
		git=invoke(['git', 'rev-parse', 'HEAD']), tools={}, firmware=[],
		guest_execution=False, target_approval=False)
	for name in ['qemu-system-aarch64', 'qemu-system-riscv64', 'qemu-system-arm',
		'qemu-system-x86_64', 'qemu-system-i386', 'clang', 'llc', 'ld.lld',
		'llvm-readelf', 'llvm-objdump', 'llvm-objcopy', 'readelf', 'objdump']:
		path = shutil.which(name)
		entry = dict(found=path is not None)
		result['tools'][name] = entry
		if path is None:
			continue
		entry['executable'] = identity(path)
		entry['version'] = invoke([path, '--version'])
		if name.startswith('qemu-system-'):
			entry['machines'] = invoke([path, '-machine', 'help'])
			entry['cpus'] = invoke([path, '-cpu', 'help'])
			entry['accelerators'] = invoke([path, '-accel', 'help'])
		elif name == 'clang':
			entry['targets'] = invoke([path, '--print-targets'])
	for directory, pattern in [('/usr/share/seabios', '*.bin'),
		('/usr/share/edk2/ovmf', '*.fd'), ('/usr/share/qemu', 'qboot.rom')]:
		for path in sorted(Path(directory).glob(pattern)):
			if path.is_file():
				result['firmware'].append(identity(path))
	qemu = result['tools']['qemu-system-x86_64']
	result['candidates'] = []
	if qemu['found'] and qemu['version'].get('exit') == 0:
		machines = qemu['machines'].get('stdout', '')
		firmware = {Path(row['path']).name for row in result['firmware']}
		if 'pc-i440fx-10.2' in machines and 'bios-256k.bin' in firmware:
			result['candidates'].append(dict(target='x86_64-none-elf',
				machine='pc-i440fx-10.2', cpu='qemu64', accelerator='tcg',
				memory_mib=64, firmware='/usr/share/seabios/bios-256k.bin',
				boot_contract='Multiboot 1 loader; explicit 32-bit to long-mode startup',
				status='discovered; approval and actual guest qualification required'))
	return result


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--output', type=Path, required=True)
	args = parser.parse_args()
	destination = args.output.resolve()
	if destination.is_relative_to(ROOT):
		parser.error('raw probe receipts belong in the external runtime directory')
	if destination.exists():
		parser.error('receipt already exists; preserve it and choose another filename')
	result = probe()
	with destination.open('x') as stream:
		json.dump(result, stream, indent=2)
		stream.write('\n')
	print(json.dumps(dict(receipt=str(destination),
		candidates=result['candidates'], guest_execution=False), indent=2))


if __name__ == '__main__':
	main()
