# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public runtime selection, real Linux no-libc execution and ELF admission."""
from pathlib import Path
import sys
from support import Evidence, ROOT


def main(compiler, output):
	e = Evidence(compiler, output, 'minimal')
	apps = ROOT / 'examples/systems-dsp-9'
	start = e.output / 'linux-start.o'
	e.run(['clang', '-c', apps/'linux-start.S', '-o', start])
	e.run([e.compiler, '--target-info'], contains='pointer-bits=64')
	e.run([e.compiler, '--target-info', '--target=aarch64-none-elf'], contains='target=aarch64-none-elf')
	for level in (0, 1, 2):
		obj = e.output / f'crc-O{level}.o'
		exe = e.output / f'crc-O{level}'
		e.run([e.compiler, '--runtime=none', '-c', f'-O{level}', apps/'a65-crc.astra', '-o', obj])
		e.run(['ld.lld', '-m', 'elf_x86_64', '-static', '--no-undefined', '-e', '_start',
			'-Map='+str(exe)+'.map', start, obj, '-o', exe])
		e.run([exe], stdout='')
		dynamic = e.run(['readelf', '-d', exe]).stdout
		assert 'NEEDED' not in dynamic and 'There is no dynamic section' in dynamic
		assert 'INTERP' not in e.run(['readelf', '-l', exe]).stdout
		e.run(['nm', '-u', exe], stdout='')
		e.run(['nm', '-u', obj], stdout='')
		e.run(['readelf', '-r', obj])
		e.run(['objdump', '-dr', exe], contains='syscall')
		host = e.output / f'crc-host-O{level}'
		e.run(['clang', ROOT/'tests/systems-dsp-9/host-start.c', obj, '-o', host])
		e.run([host], stdout='')
		assert 'libc.so' in e.run(['readelf', '-d', host]).stdout
		e.files(obj, exe, host, Path(str(exe)+'.map'))
	bad = e.output/'requires-host.astra'
	bad.write_text('class Item { init() {} } int main() { var item = new Item(); return 0; }\n')
	for label, arguments, expected, message in [
		('source', ['--runtime=none', '-c', bad], 1, 'runtime none'),
		('entry', ['--runtime=none', apps/'a65-crc.astra'], 2, 'requires numeric'),
		('provider', ['--runtime=none', '-c', '--vapi', ROOT/'tests/own-field/fixtures/resources.vapi', bad], 2, 'without entry wrappers'),
		('target', ['--target=sh4-none-elf', '-c', apps/'a65-crc.astra'], 2, 'unsupported target'),
		('cross-hosted', ['--target=aarch64-none-elf', '-c', apps/'a65-crc.astra'], 2, 'requires runtime none'),
		('runtime', ['--runtime=magic', '-c', apps/'a65-crc.astra'], 2, 'unsupported runtime'),
		('cpu', ['--cpu=avx512', '-c', apps/'a65-crc.astra'], 2, 'unknown option'),
	]:
		product = e.output / (label+'.o')
		e.run([e.compiler, *arguments, '-o', product], expected=expected, contains=message)
		assert not product.exists()
	mutant = e.output/'crc-bad-expected.astra'
	mutant.write_text((apps/'a65-crc.astra').read_text().replace('3421780262', '3421780263'))
	obj, exe = e.output/'crc-mutant.o', e.output/'crc-mutant'
	e.run([e.compiler, '--runtime=none', '-c', '-O2', mutant, '-o', obj])
	e.run(['ld.lld', '-static', '--no-undefined', '-e', '_start', start, obj, '-o', exe])
	e.run([exe], expected=65, stdout='')
	e.run([e.output/'crc-O2'], stdout='')
	debug_obj, debug_exe = e.output/'crc-debug.o', e.output/'crc-debug'
	e.run([e.compiler, '--runtime=none', '-g', '-c', '-O0', apps/'a65-crc.astra', '-o', debug_obj])
	e.run(['ld.lld', '-static', '--no-undefined', '-e', '_start', start, debug_obj, '-o', debug_exe])
	e.run([debug_exe], stdout='')
	e.run(['llvm-dwarfdump', '--verify', debug_exe], contains='No errors.')
	e.run(['nm', '-u', debug_exe], stdout='')
	e.files(debug_obj, debug_exe)
	e.files(apps/'a65-crc.astra', apps/'linux-start.S', ROOT/'tests/systems-dsp-9/host-start.c')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
