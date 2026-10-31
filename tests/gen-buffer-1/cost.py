# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Measured retained code/storage/dependencies and internal freestanding startup."""
from pathlib import Path
import importlib.util
import json
import re
import sys
sys.dont_write_bytecode = True

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('observer',ROOT/'tests/struct-elem-1/execute.py');observer=importlib.util.module_from_spec(spec);spec.loader.exec_module(observer)
run=observer.run


def qualify(compiler,out):
	out.mkdir(parents=True,exist_ok=False);rows=[]
	record='struct S{int x;f64 y;}struct Box<T>{T value;}T at<T>(T[] a,int i){return a[i];}'
	sources={
		'old-scalar-vector':'T id<T>(T value){T local=value;return local;}int f(int value){return id(value);}int<4> v(int<4> value){return id(value);}',
		'ordinary-record':'struct S{int x;f64 y;}S f(S value){S local=value;return local;}',
		'generic-scalar':'int f(int[] values,int value){fill(values,value);swap_elements(values,0,1);return 0;}',
		'generic-record':record+'S f(S[] values,S value){fill(values,value);swap_elements(values,0,1);return at(values,0);}',
		'nested-generic-record':record+'Box<Box<S>> f(Box<Box<S>>[] values,Box<Box<S>> value){fill(values,value);return at(values,0);}',
		'large-record':'struct Big{'+''.join('int f'+str(i)+';' for i in range(256))+'}owned Big[] f(Big[] values){return clone_array(values);}',
		'owner-consumer':'void consume<T>(owned T[] a){}void f(owned int[] a){consume(move a);}',
		'owner-relay':'owned T[] relay<T>(owned T[] a){return move a;}owned int[] f(owned int[] a){return relay(move a);}',
		'generic-clone':record+'owned S[] f(S[] values){return clone_array(values);}',
		'generic-fill':record+'owned S[] f(int n,S value){return filled_array(n,value);}',
		'generic-replacement':record+'void f(owned S[] values){values=clone_array(values);}',
		'allocated-record-array':record+'owned S[] f(int n){var values=new S[n];S value={x=42,y=3.5d};fill(values,value);return move values;}',
	}
	for name,source in sources.items():
		path=out/(name+'.astra');path.write_text(source+'\n');ir=run([compiler,'--dump-llvm',ROOT/'lib/astra/base/slices.astra',ROOT/'lib/astra/base/buffers.astra',path]);(out/(name+'.llvm')).write_text(ir)
		if name in ['old-scalar-vector','ordinary-record','generic-record','nested-generic-record']:assert 'alloca' not in ir and '@calloc' not in ir and '@free' not in ir
		for mode in ['O0','O2','O2-fma','preserved-O2']:
			stem=name+'-'+mode;inp,opt,obj=out/(stem+'-input.ll'),out/(stem+'.ll'),out/(stem+'.o')
			retained=re.sub(r'^define internal fastcc ','define fastcc ',ir,flags=re.M)
			inp.write_text(re.sub(r'^define fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',retained,flags=re.M) if mode=='preserved-O2' else retained)
			run(['opt','-passes=verify' if mode=='O0' else '-passes=default<O2>','-S',inp.name,'-o',opt.name],out);run(['llc','-O0' if mode=='O0' else '-O2','-filetype=obj','-relocation-model=pic',*(['-mattr=+fma'] if mode=='O2-fma' else []),opt.name,'-o',obj.name],out)
			sizes=run(['size','-A',obj]);undefined=run(['nm','-u',obj]);(out/(stem+'.size')).write_text(sizes);(out/(stem+'.undefined')).write_text(undefined);(out/(stem+'.machine')).write_text(run(['objdump','-dr',obj]));(out/(stem+'.symbols')).write_text(run(['readelf','-h','-Ws','-r',obj]))
			if name not in ['large-record','allocated-record-array','owner-consumer','owner-relay','generic-clone','generic-fill','generic-replacement']:assert not undefined,(name,undefined)
			if name=='owner-consumer':assert 'free' in undefined and 'calloc' not in undefined
			if name in ['generic-clone','generic-fill','generic-replacement']:assert 'calloc' in undefined
			if name=='generic-replacement':assert 'free' in undefined
			sections={name:int(size) for name,size in re.findall(r'^(\.\S+)\s+(\d+)\s+\d+',sizes,re.M)}
			rows.append(dict(name=stem,sections=sections,undefined=undefined,source_allocas=ir.count('alloca ')))
	assembly=out/'start.S';assembly.write_text('.text\n.global _start\n_start:\n\txor %ebp,%ebp\n\tand $-16,%rsp\n\tcall main\n\tmov %eax,%edi\n\tmov $60,%eax\n\tsyscall\n.section .note.GNU-stack,"",@progbits\n')
	path=out/'freestanding.astra';path.write_text(record+'int main(){S input={x=42,y=3.5d};S[2] values={input,input};fill(slice(values),input);swap_elements(slice(values),0,1);var saved=at(slice(values),1);return saved.x-42;}\n')
	ssa=run([compiler,'--dump-ssa',ROOT/'lib/astra/base/slices.astra',ROOT/'lib/astra/base/buffers.astra',path]);ir=run([compiler,'--dump-llvm',ROOT/'lib/astra/base/slices.astra',ROOT/'lib/astra/base/buffers.astra',path]);ordinal=re.search(r'\(function #(\d+) "main" -> int',ssa)[1]
	ir+='\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.'+ordinal+'()\n\tret i32 %r\n}\n'
	for mode in ['O0','O2','preserved-O2']:
		stem='freestanding-'+mode;inp,opt,obj=out/(stem+'-input.ll'),out/(stem+'.ll'),out/(stem+'.o');inp.write_text(re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',ir,flags=re.M) if mode=='preserved-O2' else ir)
		run(['opt','-passes=verify' if mode=='O0' else '-passes=default<O2>','-S',inp.name,'-o',opt.name],out);run(['llc','-O0' if mode=='O0' else '-O2','-filetype=obj',opt.name,'-o',obj.name],out);assert not run(['nm','-u',obj])
		for cc in ['gcc','clang']:
			exe=out/(stem+'-'+cc);run([cc,'-nostdlib','-static',*(['-no-pie'] if cc=='gcc' else []),assembly,obj,'-o',exe]);assert run([exe])=='';assert not run(['nm','-u',exe]);rows.append(dict(name=exe.name,freestanding=True,status=0,undefined=''))
		(out/(stem+'.machine')).write_text(run(['objdump','-dr',obj]));(out/(stem+'.size')).write_text(run(['size','-A',obj]))
	(out/'results.json').write_text(json.dumps(rows,indent='\t')+'\n');print('48 measured objects and 6 freestanding executions; borrowing, allocation and cleanup dependencies separated')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve())
