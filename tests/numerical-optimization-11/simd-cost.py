"""Measured vector PCM and independent scalar-source implementation."""
from pathlib import Path
import json
import random
import re
import sys
import evidence as support
from ablation import distribution, probe


def main(compiler,output):
	e=support.Evidence(compiler,output,'simd-cost')
	source=support.ROOT/'examples/numerical-optimization-11/a87-pcm.astra'
	libs=[support.ROOT/'lib/astra/numerics'/name for name in ('vectors.astra','pcm.astra')]
	oracle=Path(__file__).with_name('application-oracle.c')
	e.inputs(source,*libs,oracle,Path(__file__),Path(__file__).with_name('ablation.py'))
	text=source.read_text(); old='for(int i=0;i<48000;i=i+8){store_i16x8(output,i,pcm_mix8(load_i16x8(a,i),load_i16x8(b,i)));}'
	assert text.count(old)==1
	scalar=e.output/'pcm-scalar.astra'; scalar.write_text(text.replace(old,'for(int i=0;i<48000;i=i+1){output[i]=pcm_mix(a[i],b[i]);}'))
	provider=e.output/'oracle.o'
	e.run(['clang','-std=c11','-O2','-ffp-contract=off','-fno-fast-math','-Wall','-Wextra','-Werror','-DAPP_ID=87','-c',oracle,'-o',provider])
	products={}; outputs=[]; rows={}
	for name,selected in [('vector',source),('scalar-source',scalar)]:
		for level in (0,1,2):
			exe=e.output/f'{name}-O{level}'
			e.run([e.compiler,f'-O{level}',selected,*libs,'--link-object',provider,'--link-library','m','-o',exe])
			binary=exe.with_suffix('.bin'); e.run([exe],env={'ASTRA_NUMERICAL_OUTPUT':str(binary)},contains='numerical:A87:48000')
			assert binary.stat().st_size==48000*8; outputs.append(binary.read_bytes())
			e.run(['valgrind','--quiet','--error-exitcode=91','--leak-check=full','--errors-for-leak-kinds=all',exe],contains='numerical:A87:48000')
			ir=exe.with_suffix('.ll');ir.write_text(e.run([e.compiler,'--dump-llvm',f'-O{level}',selected,*libs]).stdout)
			asm=exe.with_suffix('.asm');asm.write_text(e.run(['objdump','-d','--no-show-raw-insn',exe]).stdout)
			e.files(exe,binary,ir,asm)
			if level==2:
				products[name]=exe; rows[name]=dict(executable=support.parent.identity(exe),packed_saturating_add_instructions=len(re.findall(r'\bpaddsw\b',asm.read_text())),warm_seconds=[])
				for warm in range(2):e.run([exe])
	assert all(value==outputs[0] for value in outputs)
	randomizer=random.Random(110087)
	for repeat in range(11):
		order=list(products);randomizer.shuffle(order)
		for name in order:e.run([products[name]]);rows[name]['warm_seconds'].append(e.data['commands'][-1]['seconds'])
	for name,row in rows.items():
		row['warm_seconds']=distribution(row['warm_seconds']);row['counter_probe']=probe(['perf','stat','-x,','-e','instructions,cycles',str(products[name])])
	result=dict(work_items=48000,seed=110087,observations=rows,target=e.run([e.compiler,'--target-info']).stdout,
		cpu=probe(['lscpu','--json']),limits=['Scalar source is independent. LLVM may vectorize legal scalar work at O2; no scalar-ISA promise.','Process times include the identical C generation/reference and startup. No universal throughput claim.'])
	path=e.output/'measurements.json';path.write_text(json.dumps(result,indent=2)+'\n');e.files(path,scalar,provider)
	e.complete()


if __name__=='__main__':main(*sys.argv[1:])
