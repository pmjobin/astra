# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual PC MMIO/UART, ordered atomics and breakpoint entry/return."""
from pathlib import Path
import sys
from guest import Evidence, ROOT, image, boot


def main(compiler, output):
	e = Evidence(compiler, output, 'guest-devices')
	apps = ROOT / 'examples/freestanding-allocation-12'
	library = ROOT / 'lib/astra/platform/pc-devices.astra'
	for level in (0, 1, 2):
		for name, expected, defines, devices in [
			('a99-device-order', 'EDU:OK\n', ['-DASTRA_PC_EDU'], ['-device', 'edu,addr=04.0']),
			('a100-trap-return', 'TRAP:41\n', ['-DASTRA_PC_TRAP'], []),
		]:
			source = apps / (name + '.astra')
			binary = image(e, source, f'{name}-O{level}', level,
				defines, [library])
			boot(e, binary, expected, devices=devices)
			ir = e.run([e.compiler, '--target=x86_64-none-elf', '--runtime=none',
				f'-O{level}', '--dump-llvm', library, source]).stdout
			path = e.output / f'{name}-O{level}.ll'
			path.write_text(ir)
			e.files(path)
			if name.startswith('a99'):
				assert 'store volatile i32' in ir and 'load volatile i32' in ir
				assert 'atomicrmw add' in ir and 'seq_cst' in ir
				assert 'acquire' in ir and 'release' in ir
				assembly = e.run(['llvm-objdump', '-d', binary.with_suffix('.elf')]).stdout
				assert 'lock' in assembly and 'xadd' in assembly
			else:
				assembly = e.run(['llvm-objdump', '-d', binary.with_suffix('.elf')]).stdout
				assert 'iretq' in assembly and 'int3' in assembly
	for name, text, message in [
		('wrong-width', '[CCode(device="pc-edu-read32")] extern(C) i64 read();', 'exact i32 signature'),
		('wrong-order', '[CCode(device="pc-atomic-store-acquire")] extern(C) int store(int v);', 'invalid PC device policy'),
		('wrong-arity', '[CCode(device="pc-edu-write32")] extern(C) int write();', 'exact i32 signature'),
		('raw-address', '[CCode(device="pc-edu-read32")] extern(C) int read(void* address);', 'exact i32 signature'),
		('missing-handler', '[CCode(device="pc-breakpoint")] extern(C) int trap(int v); export(C) int astra_entry(int a,int b,int c){return trap(1);}', 'requires the exact source-defined'),
		('bad-handler', 'export(C) int astra_trap_handler(int one){return one;}', 'PC trap handler requires exact'),
		('implicit-handler-cleanup', '[CCode(device="pc-uart-tx8")] extern(C) int byte(int v);class Guard{int value;deinit(){byte(65);}}export(C) int astra_trap_handler(int a,int b){Guard local={value=a};return a+b;}', 'cannot acquire storage ownership or implicit cleanup'),
	]:
		source = e.output / (name + '.astra')
		product = e.output / (name + '.o')
		source.write_text(text + '\n')
		e.run([e.compiler, '--runtime=none', '--target=x86_64-none-elf', '-c',
			source, '-o', product], expected=1, contains=message)
		assert not product.exists()
	product = e.output / 'host-device.o'
	e.run([e.compiler, '-c', library, apps / 'a99-device-order.astra', '-o', product],
		expected=1, contains='PC device policies require')
	assert not product.exists()
	# The same audited binary must refuse a machine lacking its selected device.
	boot(e, e.output / 'a99-device-order-O2.bin', '', exit=253)
	# An invalid runtime byte goes through Astra's emitted guard and #UD panic.
	bad_byte = e.output / 'a99-byte-overflow.astra'
	bad_byte.write_text((apps / 'a99-device-order.astra').read_text().replace('write_byte(69)', 'write_byte(256)'))
	boot(e, image(e, bad_byte, 'a99-byte-overflow', 2,
		['-DASTRA_PC_EDU'], [library]), 'PANIC:06\n', exit=253,
		devices=['-device', 'edu,addr=04.0'])
	bad_arithmetic = e.output / 'a100-division-zero.astra'
	bad_arithmetic.write_text('export(C) int astra_entry(int index,int initialized,int zeroed){int divisor=index;return 19/divisor;}\n')
	boot(e, image(e, bad_arithmetic, 'a100-division-zero', 2),
		'PANIC:06\n', exit=253)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
