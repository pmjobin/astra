# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
from pathlib import Path
import sys
import evidence as support

ROOT=support.ROOT


def main(compiler,output):
	e=support.Evidence(compiler,output,'portability')
	base=ROOT/'tests/numerical-optimization-11'
	source=base/'no-libc.astra'
	libraries=[ROOT/'lib/astra/numerics'/(name+'.astra') for name in ['vectors','complex','pcm']]
	start=e.output/'start.o'
	e.inputs(source,*libraries,base/'no-libc-start.S',Path(__file__))
	e.run(['clang','-c','-ffreestanding','-fno-stack-protector',base/'no-libc-start.S','-o',start])
	for level in (0,1,2):
		for mode in ('native','scalar'):
			env={'ASTRA_TEST_VECTOR_MEMORY':mode}
			obj,exe=e.output/f'numeric-{mode}-O{level}.o',e.output/f'numeric-{mode}-O{level}'
			e.run([e.compiler,'--runtime=none','-c',f'-O{level}',source,*libraries,'-o',obj],env=env)
			e.run(['ld.lld','-static','--no-undefined','-e','_start',start,obj,'-o',exe])
			e.run([exe],stdout='numerics-no-libc\n')
			assert not e.run(['nm','-u',exe]).stdout.strip()
			dynamic=e.run(['readelf','-d',exe]).stdout
			assert 'NEEDED' not in dynamic
			assembly=e.output/f'{mode}-O{level}.asm';assembly.write_text(e.run(['objdump','-dr',exe]).stdout)
			e.files(obj,exe,assembly)
			# Allocation is still outside this profile even though borrowed numeric views
			# are admitted. Failure must precede creation of a product.
	bad=e.output/'owned.astra';bad.write_text('int f(){owned f32[] a=new f32[4];return 0;}\n')
	product=e.output/'owned.o'
	e.run([e.compiler,'--runtime=none','-c',bad,'-o',product],expected=1,contains='runtime none')
	assert not product.exists()
	e.files(start,bad);e.complete()


if __name__=='__main__':main(*sys.argv[1:])
