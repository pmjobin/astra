"""A93 checked-failure counterexample: the throwing helper must stay on heap."""
from pathlib import Path
import re
import sys
import evidence as support


def main(compiler,output):
	e=support.Evidence(compiler,output,'packet-checked')
	original=support.ROOT/'examples/numerical-optimization-11/a93-packet.astra'
	errors=support.ROOT/'lib/astra/base/errors.astra';oracle=Path(__file__).with_name('packet-oracle.c')
	e.inputs(original,errors,oracle,Path(__file__))
	text=original.read_text().split('int main(){',1)[0]
	text=text.replace('f64 transform_packet(int sequence,f64 sample){','f64 transform_packet(int sequence,f64 sample) throws Error{')
	text=text.replace('if(sequence%97==0){return packet.transform(0.5);}','if(sequence%113==0){throw new Error("packet boundary");}\n\tif(sequence%97==0){return packet.transform(0.5);}')
	text='extern(C) void packet_checked_failure(int sequence);\nextern(C) int packet_checked_count();\n'+text
	text+='''int main(){
	for(int i=0;i<48000;i=i+1){
		f64 sample=packet_sample(i);f64 value=0.0;
		try {value=transform_packet(i,sample);}
		catch(Error error){
			if(error.message!="packet boundary"){return 2;}
			packet_checked_failure(i);
			f64 gain=0.75;if(i%97==0){gain=0.5;}
			value=sample*gain+((i%7) as f64)/16.0;
		}
		if(packet_observe(i,value)!=0){return 1;}
	}
	if(packet_checked_count()!=425){return 3;}
	return packet_finish(48000);
}
'''
	source=e.output/'checked.astra';source.write_text(text)
	ssa=e.run([e.compiler,'--dump-ssa',source,errors],env={'ASTRA_EXPLAIN_OPTIMIZATIONS':'1'}).stdout
	assert 'stack-object' not in ssa, 'checked throwing lifetime is outside the promotion proof'
	provider=e.output/'oracle.o';e.run(['clang','-std=c11','-O2','-ffp-contract=off','-fno-fast-math','-fno-builtin','-Wall','-Wextra','-Werror','-c',oracle,'-o',provider])
	observer=e.output/'checked-observer.c';observer.write_text('#include <stdlib.h>\nstatic int failures;\nvoid packet_checked_failure(int sequence){if(sequence%113!=0)abort();failures++;}\nint packet_checked_count(void){return failures;}\n')
	observer_obj=e.output/'checked-observer.o';e.run(['clang','-std=c11','-O2','-Wall','-Wextra','-Werror','-c',observer,'-o',observer_obj])
	outputs=[];counts=[]
	for level in (0,1,2):
		for mode in ('off','on'):
			exe=e.output/f'checked-O{level}-{mode}'
			e.run([e.compiler,f'-O{level}',source,errors,'--link-object',provider,'--link-object',observer_obj,'-o',exe],env={'ASTRA_TEST_OPTIMIZATIONS':mode})
			data=exe.with_suffix('.bin');result=e.run([exe],env={'ASTRA_NUMERICAL_OUTPUT':str(data)},contains='numerical:A93:48000 retired=48000')
			counts.append(int(re.search(r'calloc=(\d+)',result.stdout)[1]));assert counts[-1]>=48000
			outputs.append(data.read_bytes());assert data.stat().st_size==48000*8
			e.run(['valgrind','--default-suppressions=no','--error-exitcode=91','--leak-check=full','--errors-for-leak-kinds=all',exe],contains='failed=0')
			e.files(exe,data)
	assert len(set(counts))==1 and all(value==outputs[0] for value in outputs)
	e.data['checked_failures']=425;e.data['allocation_calls']=counts[0]
	e.files(source,provider,observer,observer_obj);e.complete()


if __name__=='__main__':main(*sys.argv[1:])
