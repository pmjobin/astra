# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
import sys
from support import Evidence, ROOT


def main(compiler, output):
	e = Evidence(compiler, output, 'numeric')
	for family, macro, app, expected in [
		('f64', 'ORACLE_F64', 'a66-filter.astra', 'f64x2:2048 vectors;8192 exact lanes;NaNs classified\n'),
		('integer', 'ORACLE_INTEGER', 'a67-mixer.astra', 'saturation:2048 pairs;signed64,unsigned64,PCM16 exact\n'),
	]:
		provider = e.output/(family+'-oracle.o')
		e.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-fast-math', '-Wall', '-Wextra', '-Werror',
			'-D'+macro, '-c', ROOT/'tests/systems-dsp-9/numeric-oracle.c', '-o', provider])
		source = ROOT/'examples/systems-dsp-9'/app
		for level in (0, 1, 2):
			exe = e.output/f'{family}-O{level}'
			e.run([e.compiler, f'-O{level}', source, '--link-object', provider, '-o', exe])
			e.run([exe], stdout=expected)
			ir = e.run([e.compiler, '--dump-llvm', f'-O{level}', source]).stdout
			assert not any(flag in ir for flag in [' fast ', ' reassoc ', ' contract ', 'llvm.fma', 'llvm.fmuladd'])
			(e.output/f'{family}-O{level}.ll').write_text(ir)
			assembly = e.run(['objdump', '-dr', exe]).stdout
			(e.output/f'{family}-O{level}.asm').write_text(assembly)
			if family == 'f64':
				assert '<2 x double>' in ir
				if level == 2:
					assert 'mulpd' in assembly and 'addpd' in assembly and 'divpd' in assembly
			e.files(exe, e.output/f'{family}-O{level}.ll', e.output/f'{family}-O{level}.asm')
		e.files(provider, source)
	for name, text, message in [
		('dimension', 'int main(){f64<4> x={1.0,2.0,3.0,4.0};return 0;}', 'unsupported VEC-1 vector shape'),
		('lane', 'int main(){f64<2> x={1.0f,2.0};return 0;}', 'vector lane expects exact'),
		('sign', 'int main(){i64<2> a={1,2};u64<2> b={1,2};var c=sat_add(a,b);return 0;}', 'exact matching'),
		('f64-sat', 'int main(){f64<2> a={1.0,2.0};var c=sat_add(a,a);return 0;}', 'saturation requires'),
	]:
		bad, product = e.output/(name+'.astra'), e.output/(name+'.o')
		bad.write_text(text+'\n')
		e.run([e.compiler, '-c', bad, '-o', product], expected=1, contains=message)
		assert not product.exists()
	e.files(ROOT/'tests/systems-dsp-9/numeric-oracle.c')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
