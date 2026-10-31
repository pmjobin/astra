# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bounded/aligned vector memory, whole-value overlap and scalar fallback."""
from pathlib import Path
import sys
import tempfile

import evidence as support
ROOT = support.ROOT


def main(compiler, output):
	e = support.Evidence(compiler, output, 'memory')
	base = ROOT/'tests/numerical-optimization-11'
	source, library, oracle = base/'memory.astra', ROOT/'lib/astra/numerics/vectors.astra', base/'floating-oracle.c'
	provider = e.output/'oracle.o'
	e.inputs(source,library,oracle,Path(__file__))
	e.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-fast-math', '-Wall', '-Wextra', '-Werror', '-c', oracle, '-o', provider])
	for stage in ('semantics','core','cfg','ssa','nabi'):
		text=e.run([e.compiler,'--dump-'+stage,source,library]).stdout
		assert 'vector-memory' in text and 'dot-f64' in text if stage!='nabi' else 'vector-memory' in text
		(e.output/('memory.'+stage)).write_text(text)
	for level in (0,1,2):
		for mode in ('native','scalar'):
			env={'ASTRA_TEST_VECTOR_MEMORY':mode}
			exe=e.output/f'memory-{mode}-O{level}'
			e.run([e.compiler,f'-O{level}',source,library,'--link-object',provider,'--link-library','m','-o',exe],env=env)
			e.run([exe])
			e.run(['valgrind','--quiet','--error-exitcode=91','--leak-check=full','--errors-for-leak-kinds=all',exe])
			text=e.run([e.compiler,'--dump-llvm',f'-O{level}',source,library],env=env).stdout
			if level==0:
				assert 'vector.bounds' in text and 'vector.alignment' in text
				assert 'load <4 x float>' in text if mode=='native' else '.scalar.load' in text
			ir,assembly=e.output/f'{mode}-O{level}.ll',e.output/f'{mode}-O{level}.asm'
			ir.write_text(text);assembly.write_text(e.run(['objdump','-dr',exe]).stdout);e.files(exe,ir,assembly)
	negative_root=Path(tempfile.mkdtemp(prefix='negative-',dir=e.output))
	for name,body,runtime in [
		('raw-pointer','f32 a=0.0f;f32<4> x=load_vector(&a,0,4,1);',False),
		('short-borrow','f32[3] a={0.0f,0.0f,0.0f};f32<4> x=load_f32x4(slice(a),0);',True),
		('short-store','f32[3] a={0.0f,0.0f,0.0f};store_f32x4(slice(a),0,splat(1.0f,4));',True),
		('misalignment','owned f32[] a=new f32[8];f32<4> x=load_aligned_f32x4(a,1);',True),
		('bad-alignment','f32[4] a={0.0f,0.0f,0.0f,0.0f};f32<4> x=load_vector(slice(a),0,4,3);',False),
		('wrong-width','f32[4] a={0.0f,0.0f,0.0f,0.0f};f64<2> x=load_vector(slice(a),0,4,1);',False),
		('wrong-store','f32[4] a={0.0f,0.0f,0.0f,0.0f};f64<2> b={1.0,2.0};store_vector(slice(a),0,b,1);',False),
		('huge-offset','f32[4] a={0.0f,0.0f,0.0f,0.0f};f32<4> x=load_f32x4(slice(a),2147483647);',True),
	]:
		bad,product=negative_root/(name+'.astra'),negative_root/name
		bad.write_text('using Numerics; int main(){'+body+'return 0;}\n')
		e.files(bad)
		e.run([e.compiler,bad,library,'-o',product],expected=0 if runtime else 1)
		if runtime:e.run([product],expected=-4)
		else:assert not product.exists()
	e.files(source,library,oracle,provider);e.complete()


if __name__=='__main__':main(*sys.argv[1:])
