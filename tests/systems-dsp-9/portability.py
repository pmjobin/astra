# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
import sys
from support import Evidence, ROOT
from arena import ARENA_INPUTS


def main(compiler, output):
	e = Evidence(compiler, output, 'portability')
	apps = ROOT/'examples/systems-dsp-9'
	e.run(['llc', '--version'], contains='aarch64')
	e.run(['llvm-config', '--version'], contains='22.')
	cross_info = e.run([e.compiler, '--target=aarch64-none-elf', '--target-info']).stdout
	assert 'pointer-bits=64' in cross_info and 'runtimes=none' in cross_info and 'data-layout=e-' in cross_info
	reference = e.output/'aarch64-clang-layout.o'
	e.run(['clang', '--target=aarch64-none-elf', '-ffreestanding', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', ROOT/'tests/systems-dsp-9/aarch64-layout.c', '-o', reference])
	e.run(['readelf', '-h', reference], contains='AArch64')
	e.run(['llvm-objdump', '-dr', reference], contains='c_identity')
	e.files(reference, ROOT/'tests/systems-dsp-9/aarch64-layout.c')
	for producer_level, consumer_level in [(0,0), (2,2), (0,2), (2,0), (1,1)]:
		module = e.output/f'numeric-O{producer_level}'
		obj, interface = module.with_suffix('.o'), module.with_suffix('.nabi')
		e.run([e.compiler, '-g', f'-O{producer_level}', '-c', '--module', 'NumericUnit', '--native-export', 'NumericUnit.kernel', '--emit-interface', interface, apps/'numeric-unit.astra', '-o', obj])
		exe = e.output/f'a71-{producer_level}-{consumer_level}'
		e.run([e.compiler, '-g', f'-O{consumer_level}', '--import-module', interface, apps/'a71-consumer.astra', '-o', exe])
		e.run([exe], stdout='')
		e.run(['llvm-dwarfdump', '--verify', exe], contains='No errors.')
		e.files(obj, interface, exe)
		e.run([e.compiler, '--format', '--check', apps/'a71-consumer.astra'])
	unit_lines = (apps/'numeric-unit.astra').read_text().splitlines()
	state_line = next(i for i, line in enumerate(unit_lines, 1) if 'int state' in line)
	e.run(['gdb', '--nx', '--batch', '-ex', 'set debuginfod enabled off', '-ex', f'break {apps/"numeric-unit.astra"}:{state_line}',
		'-ex', 'run', '-ex', 'print input', '-ex', 'continue', e.output/'a71-0-0'], contains='$1 = 4', env=dict(DEBUGINFOD_URLS=''))
	tampered = e.output/'numeric-wrong-target.nabi'
	interface_text = (e.output/'numeric-O0.nabi').read_text()
	target = e.run([e.compiler, '--target-info']).stdout.splitlines()[0].split('=',1)[1]
	assert target in interface_text
	tampered.write_text(interface_text.replace(target, 'aarch64-none-elf'))
	product = e.output/'a71-wrong-target'
	e.run([e.compiler, '--import-module', tampered, apps/'a71-consumer.astra', '-o', product], expected=1, contains='target triple/data layout mismatch')
	assert not product.exists()
	e.run([e.output/'a71-0-0'], stdout='')
	for level in (0, 2):
		obj = e.output/f'a71-aarch64-O{level}.o'
		e.run([e.compiler, '--runtime=none', '--target=aarch64-none-elf', '-c', f'-O{level}', apps/'numeric-unit.astra', apps/'a71-cross.astra', '-o', obj])
		header = e.run(['readelf', '-h', obj]).stdout
		assert 'AArch64' in header and 'REL (Relocatable file)' in header and 'little endian' in header
		e.run(['nm', '-u', obj], stdout='')
		e.run(['llvm-objdump', '-dr', obj], contains='numeric_kernel')
		e.run(['readelf', '-r', obj])
		e.files(obj)
	start = e.output/'linux-start.o'
	provider = e.output/'packet-provider.o'
	e.run(['clang', '-c', apps/'linux-start.S', '-o', start])
	e.run(['clang', '-D_GNU_SOURCE', '-c', apps/'packet-provider.c', '-o', provider])
	for level in (0, 1, 2):
		obj, minimal = e.output/f'a72-none-O{level}.o', e.output/f'a72-none-O{level}'
		e.run([e.compiler, '--runtime=none', '-c', f'-O{level}', apps/'telemetry.astra', apps/'a72-minimal.astra', '-o', obj])
		e.run(['ld.lld', '-static', '--no-undefined', '-e', '_start', start, obj, '-o', minimal])
		e.run([minimal], stdout='')
		e.run(['nm', '-u', minimal], stdout='')
		assert 'NEEDED' not in e.run(['readelf', '-d', minimal]).stdout
		host = e.output/f'a72-hosted-O{level}'
		e.run([e.compiler, f'-O{level}', *ARENA_INPUTS, apps/'telemetry.astra', apps/'a72-hosted.astra', '--link-object', provider, '-o', host])
		e.run([host], stdout='packets:1 closed:1\n')
		assert 'libc.so' in e.run(['readelf', '-d', host]).stdout
		e.files(obj, minimal, host)
	bad = e.output/'cross-provider.o'
	e.run([e.compiler, '--runtime=none', '--target=aarch64-none-elf', '-c', apps/'a66-filter.astra', '-o', bad], expected=1, contains='runtime none')
	assert not bad.exists()
	unused = e.output/'cross-unused-float.astra'
	unused.write_text('export(C) int kernel(){f64 unused=1.0;return 0;}\n')
	bad = e.output/'cross-unused-float.o'
	e.run([e.compiler, '--runtime=none', '--target=aarch64-none-elf', '-c', unused, '-o', bad], expected=1, contains='unsupported source requirement: local')
	assert not bad.exists()
	bad = e.output/'a72-hosted-in-none.o'
	e.run([e.compiler, '--runtime=none', '-c', *ARENA_INPUTS, apps/'telemetry.astra', apps/'a72-hosted.astra', '-o', bad], expected=2, contains='without entry wrappers')
	assert not bad.exists()
	e.run([e.output/'a72-hosted-O2'], stdout='packets:1 closed:1\n')
	e.data['cross_target'] = 'OBJECT_ONLY: aarch64-none-elf; no executor run'
	e.data['sh4'] = 'UNAVAILABLE: no installed SuperH backend'
	e.data['no_os'] = 'NOT_EXECUTED: no qualified startup/runtime image'
	e.files(*[apps/name for name in ['numeric-unit.astra','a71-consumer.astra','a71-cross.astra','telemetry.astra','a72-minimal.astra','a72-hosted.astra']])
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
