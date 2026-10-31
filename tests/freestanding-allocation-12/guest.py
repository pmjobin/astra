# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public Astra object -> explicit Multiboot image -> bounded no-OS QEMU."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def image(evidence, source, name, level, defines=(), extra_sources=(), link_objects=()):
	apps = ROOT / 'examples/freestanding-allocation-12'
	startup = evidence.output / (name + '-start.o')
	memory = evidence.output / (name + '-memory.o')
	obj = evidence.output / (name + '.o')
	elf = evidence.output / (name + '.elf')
	binary = evidence.output / (name + '.bin')
	evidence.run(['clang', '--target=x86_64-none-elf', '-ffreestanding',
		'-c', *defines, apps / 'pc-start.S', '-o', startup])
	evidence.run(['clang', '--target=x86_64-none-elf', '-O2', '-mno-red-zone',
		'-ffreestanding', '-fno-builtin', '-ffunction-sections', '-fno-stack-protector',
		'-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic',
		'-c', apps / 'pc-memory.c', '-o', memory])
	evidence.run(['nm', '-u', memory], stdout='')
	evidence.run([evidence.compiler, '--runtime=none', '--target=x86_64-none-elf',
		'-c', f'-O{level}', *extra_sources, source, '-o', obj])
	evidence.run(['ld.lld', '-static', '--no-undefined', '--gc-sections', '-T', apps / 'pc.ld',
		'-Map=' + str(elf) + '.map', startup, obj, memory, *link_objects, '-o', elf])
	evidence.run(['llvm-objcopy', '-O', 'binary', elf, binary])
	evidence.run(['nm', '-u', elf], stdout='')
	headers = evidence.run(['readelf', '-h', '-l', '-S', '-s', '-r', '-d', elf])
	assert 'INTERP' not in headers.stdout and 'NEEDED' not in headers.stdout
	assert 'ELF64' in headers.stdout and 'Advanced Micro Devices X86-64' in headers.stdout
	assembly = evidence.run(['llvm-objdump', '-d', elf])
	assert 'syscall' not in assembly.stdout
	evidence.files(source, *extra_sources, apps / 'pc-memory.c', startup, memory, obj, elf, binary, Path(str(elf) + '.map'))
	return binary


def boot(evidence, binary, output, exit=33, devices=()):
	return evidence.run(['qemu-system-x86_64', '-machine', 'pc-i440fx-10.2',
		'-accel', 'tcg', '-cpu', 'qemu64', '-m', '64M',
		'-bios', '/usr/share/seabios/bios-256k.bin',
		'-display', 'none', '-monitor', 'none', '-serial', 'stdio',
		'-parallel', 'none', '-nic', 'none', '-no-reboot',
		'-device', 'isa-debug-exit,iobase=0x501,iosize=1',
		*devices,
		'-kernel', binary], expected=exit, stdout=output, timeout=15)


def main(compiler, output):
	e = Evidence(compiler, output, 'guest-foundation')
	apps = ROOT / 'examples/freestanding-allocation-12'
	source = apps / 'a97-serial-checksum.astra'
	e.run([e.compiler, '--target=x86_64-none-elf', '--target-info'],
		contains='runtimes=none')
	for level in (0, 1, 2):
		binary = image(e, source, f'a97-O{level}', level)
		boot(e, binary, 'ASTRA12:042\n')
	mutant = e.output / 'a97-changed.astra'
	mutant.write_text(source.read_text().replace('sample <= 6', 'sample <= 7'))
	boot(e, image(e, mutant, 'a97-changed', 2), 'ASTRA12:056\n')
	boot(e, image(e, source, 'a97-no-data-init', 2,
		['-DASTRA_TEST_SKIP_DATA_INIT']), '!')
	# Poisoned page tables cannot boot when BSS initialization is omitted.
	# Exit zero here is a detected guest fault, never the accepted exit 33.
	boot(e, image(e, source, 'a97-no-bss-init', 2,
		['-DASTRA_TEST_SKIP_BSS_INIT']), '', exit=0)
	ir = e.run([e.compiler, '--runtime=none', '--target=x86_64-none-elf',
		'-O2', '--dump-llvm', source]).stdout
	assert 'noredzone' in ir
	e.files(apps / 'pc-start.S', apps / 'pc.ld',
		'/usr/bin/qemu-system-x86_64', '/usr/share/seabios/bios-256k.bin')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
