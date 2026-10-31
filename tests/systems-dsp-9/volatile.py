# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
from pathlib import Path
import re
import sys
from support import Evidence, ROOT


def main(compiler, output):
	e = Evidence(compiler, output, 'volatile')
	source = ROOT/'examples/systems-dsp-9/a69-registers.astra'
	provider = ROOT/'tests/systems-dsp-9/mapped-fixture.c'
	tracer = e.output/'volatile-trace'
	e.run(['clang', '-D_GNU_SOURCE', '-std=c11', '-Wall', '-Wextra', '-Werror', ROOT/'tests/systems-dsp-9/volatile-trace.c', '-o', tracer])
	for level in (0, 1, 2):
		obj, exe = e.output/f'registers-O{level}.o', e.output/f'registers-O{level}'
		e.run([e.compiler, f'-O{level}', '--entry-object', source, '-o', obj])
		e.run(['clang', '-D_GNU_SOURCE', '-std=c11', '-Wall', '-Wextra', '-Werror', '-g', obj, provider,
			'-Wl,--wrap=calloc,--wrap=free', '-o', exe])
		e.run([exe], stdout='')
		if level in (0, 2):
			e.run([tracer, exe], stdout='volatile:9 mapped accesses;exact address,width,value,order\n')
		if level == 2:
			sanitized = e.output/'registers-asan'
			e.run(['clang', '-D_GNU_SOURCE', '-g', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', obj, provider,
				'-Wl,--wrap=calloc,--wrap=free', '-o', sanitized])
			e.run([sanitized], stdout='', env=dict(ASAN_OPTIONS='detect_leaks=1:halt_on_error=1', UBSAN_OPTIONS='halt_on_error=1'))
			e.files(sanitized)
		ir = e.run([e.compiler, '--dump-llvm', f'-O{level}', source]).stdout
		(e.output/f'registers-O{level}.ll').write_text(ir)
		accesses = re.findall(r'\b(load|store) volatile (i32|i64)\b', ir)
		assert accesses == [('store','i32'),('store','i32'),('load','i32'),('store','i32'),('load','i32'),
			('store','i64'),('load','i64'),('store','i64'),('load','i64')], accesses
		assembly = e.run(['objdump', '-dr', exe]).stdout
		(e.output/f'registers-O{level}.asm').write_text(assembly)
		e.files(obj, exe, e.output/f'registers-O{level}.ll', e.output/f'registers-O{level}.asm')
	for name, text, message in [
		('width', 'int main(){u16[1] x={0};volatile_store(x[0],1);return 0;}', 'exactly u32 and u64'),
		('bounds', 'int main(){u32[1] x={0};volatile_store(x[1],1);return 0;}', 'outside [0, 1)'),
		('origin', 'int main(){void* p=null;return volatile_load(*p) as int;}', 'dereference requires'),
		('value', 'int main(){u32[1] x={0};u64 y=1;volatile_store(x[0],y);return 0;}', 'exact u32 or u64'),
		('expired', 'int main(){var x=new u32[1];release x;return volatile_load(x[0]) as int;}', 'released'),
	]:
		bad, product = e.output/(name+'.astra'), e.output/(name+'.o')
		bad.write_text(text+'\n')
		e.run([e.compiler, '-c', bad, '-o', product], expected=1, contains=message)
		assert not product.exists()
	guard = e.output/'dynamic-bounds.astra'
	guard.write_text('int main(){var words=new u32[1];int at=1;volatile_store(words[at],1);return 0;}\n')
	for level in (0, 2):
		exe = e.output/f'dynamic-bounds-O{level}'
		e.run([e.compiler, f'-O{level}', guard, '-o', exe])
		e.run([exe], expected=-4, stdout='')
	e.files(source, provider)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
