# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Distinct numerical programs, independent C references and retained outputs."""
from pathlib import Path
import sys

import evidence as support
ROOT = support.ROOT
APPS = {
	85: ('stencil', 48003, ['vectors']),
	86: ('mask-mixer', 4096, ['vectors']),
	87: ('pcm', 48000, ['vectors', 'pcm']),
	88: ('fir', 48000, ['fir']),
	89: ('biquad', 48000, ['filters']),
	90: ('dft', 4096, ['complex']),
	91: ('geometry', 48000, ['vectors', 'complex']),
}


def main(compiler, output, app):
	app = int(app)
	name, count, modules = APPS[app]
	e = support.Evidence(compiler, output, 'a'+str(app))
	source = ROOT/'examples/numerical-optimization-11'/f'a{app}-{name}.astra'
	libraries = [ROOT/'lib/astra/numerics'/(module+'.astra') for module in modules]
	provider = e.output/'oracle.o'
	oracle = ROOT/'tests/numerical-optimization-11/application-oracle.c'
	e.inputs(source,*libraries,oracle,Path(__file__))
	e.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-fast-math', '-Wall', '-Wextra', '-Werror', f'-DAPP_ID={app}', '-c', oracle, '-o', provider])
	outputs = []
	for level in (0, 1, 2):
		exe = e.output/f'a{app}-O{level}'
		e.run([e.compiler, f'-O{level}', source, *libraries, '--link-object', provider, '--link-library', 'm', '-o', exe])
		modes = (0, 1) if app == 90 else (0,)
		for mode in modes:
			data = e.output/f'a{app}-O{level}-mode{mode}.bin'
			env = {'ASTRA_NUMERICAL_OUTPUT': str(data), 'ASTRA_NUMERICAL_RELAXED': str(mode)}
			e.run([exe], contains=f'numerical:A{app}:{count} ', env=env)
			assert data.stat().st_size == count*8
			outputs.append(data.read_bytes())
			e.files(data)
			e.run(['valgrind', '--quiet', '--error-exitcode=91', '--leak-check=full', '--errors-for-leak-kinds=all', exe], contains=f'numerical:A{app}:{count} ', env={'ASTRA_NUMERICAL_RELAXED':str(mode)}, timeout=300)
		text = e.run([e.compiler, '--dump-llvm', f'-O{level}', source, *libraries]).stdout
		ir, assembly = e.output/f'a{app}-O{level}.ll', e.output/f'a{app}-O{level}.asm'
		ir.write_text(text)
		assembly.write_text(e.run(['objdump', '-dr', exe]).stdout)
		e.files(exe, ir, assembly)
	if app != 90:
		assert all(data == outputs[0] for data in outputs), 'strict output changed with optimization'
	negative, runtime = negative_source(app)
	bad, product = e.output/'negative.astra', e.output/'negative'
	bad.write_text(negative+'\n')
	if runtime:
		e.run([e.compiler, bad, *libraries, '-o', product])
		e.run([product], expected=-4)
	else:
		e.run([e.compiler, '-c', bad, *libraries, '-o', product], expected=1)
		assert not product.exists()
	e.files(source, *libraries, oracle, provider, bad)
	e.complete()


def negative_source(app):
	if app == 85:
		return 'using Numerics; int main(){f32[3] a={1.0f,2.0f,3.0f};f32<4> b=load_f32x4(slice(a),0);return b[0] as int;}', True
	if app == 86:
		return 'int main(){bool<2> m={true,false};f32<4> a=splat(0.0f,4);f32<4> b=select(m,a,a);return 0;}', False
	if app == 87:
		return 'int main(){i16<8> a=splat(1 as i16,8);u16<8> b=splat(1 as u16,8);var c=sat_add(a,b);return 0;}', False
	if app == 88:
		return 'using Numerics; int main(){f64[1] t={1.0};owned Fir64 a=new Fir64(slice(t));owned Fir64 b=move a;f64 x=a.process(1.0);return 0;}', False
	if app == 89:
		return 'using Numerics; int main(){Biquad64 state={b0=1.0,b1=0.0,b2=0.0,a1=0.0,a2=0.0,z1=0.0};f64 x=state.process(1.0);return 0;}', False
	if app == 90:
		return 'using Numerics; int main(){Complex64 a={real=1.0,imag=0.0};Matrix2 b={m00=1.0,m01=0.0,m10=0.0,m11=1.0};Complex64 c=a.multiply(b);return 0;}', False
	if app == 91:
		return 'using Numerics; int main(){f64[1] a={1.0};f64<2> b=load_f64x2(slice(a),0);return b[0] as int;}', True
	raise AssertionError(app)


if __name__ == '__main__':
	main(*sys.argv[1:])
