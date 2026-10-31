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
	record='struct S{int x;f64 y;}struct Box<T>{T value;}T id<T>(T x){T local=x;return local;}'
	sources={
		'old-scalar-vector':'T id<T>(T value){T local=value;return local;}int f(int value){return id(value);}int<4> v(int<4> value){return id(value);}',
		'ordinary-record':'struct S{int x;f64 y;}S f(S value){S local=value;return local;}',
		'generic-record':record+'S f(S value){return id(value);}',
		'nested-generic-record':record+'Box<Box<S>> f(Box<Box<S>> value){return id(value);}',
		'record-array':record+'void f(S[] input,Box<S>[] output,int i){Box<S> box={value=id(input[i])};output[i]=id(box);}',
		'allocated-record-array':record+'owned S[] f(int n){var values=new S[n];if(n>0){S value={x=42,y=3.5d};values[0]=id(value);}return move values;}',
	}
	for name,source in sources.items():
		path=out/(name+'.astra');path.write_text(source+'\n');ir=run([compiler,'--dump-llvm',path]);(out/(name+'.llvm')).write_text(ir)
		if name in ['old-scalar-vector','ordinary-record','generic-record','nested-generic-record']:assert 'alloca' not in ir and '@calloc' not in ir and '@free' not in ir
		for mode in ['O0','O2','O2-fma','preserved-O2']:
			stem=name+'-'+mode;inp,opt,obj=out/(stem+'-input.ll'),out/(stem+'.ll'),out/(stem+'.o')
			retained=re.sub(r'^define internal fastcc ','define fastcc ',ir,flags=re.M)
			inp.write_text(re.sub(r'^define fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',retained,flags=re.M) if mode=='preserved-O2' else retained)
			run(['opt','-passes=verify' if mode=='O0' else '-passes=default<O2>','-S',inp.name,'-o',opt.name],out);run(['llc','-O0' if mode=='O0' else '-O2','-filetype=obj','-relocation-model=pic',*(['-mattr=+fma'] if mode=='O2-fma' else []),opt.name,'-o',obj.name],out)
			sizes=run(['size','-A',obj]);undefined=run(['nm','-u',obj]);(out/(stem+'.size')).write_text(sizes);(out/(stem+'.undefined')).write_text(undefined);(out/(stem+'.machine')).write_text(run(['objdump','-dr',obj]));(out/(stem+'.symbols')).write_text(run(['readelf','-h','-Ws','-r',obj]))
			if name!='allocated-record-array':assert not undefined,(name,undefined)
			sections={name:int(size) for name,size in re.findall(r'^(\.\S+)\s+(\d+)\s+\d+',sizes,re.M)}
			rows.append(dict(name=stem,sections=sections,undefined=undefined,source_allocas=ir.count('alloca ')))
	assembly=out/'start.S';assembly.write_text('.text\n.global _start\n_start:\n\txor %ebp,%ebp\n\tand $-16,%rsp\n\tcall main\n\tmov %eax,%edi\n\tmov $60,%eax\n\tsyscall\n.section .note.GNU-stack,"",@progbits\n')
	path=out/'freestanding.astra';path.write_text(record+'T choose<T>(bool use,T a,T b){T saved=b;if(use){saved=a;}return saved;}int main(){S input={x=42,y=3.5d};Box<S> box={value=id(input)};var copy=id(box);var selected=choose(true,copy.value,input);return selected.x-42;}\n')
	ssa=run([compiler,'--dump-ssa',path]);ir=run([compiler,'--dump-llvm',path]);ordinal=re.search(r'\(function #(\d+) "main" -> int',ssa)[1]
	ir+='\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.'+ordinal+'()\n\tret i32 %r\n}\n'
	for mode in ['O0','O2','preserved-O2']:
		stem='freestanding-'+mode;inp,opt,obj=out/(stem+'-input.ll'),out/(stem+'.ll'),out/(stem+'.o');inp.write_text(re.sub(r'^define internal fastcc ([^\n]+) \{$',r'define fastcc \1 noinline {',ir,flags=re.M) if mode=='preserved-O2' else ir)
		run(['opt','-passes=verify' if mode=='O0' else '-passes=default<O2>','-S',inp.name,'-o',opt.name],out);run(['llc','-O0' if mode=='O0' else '-O2','-filetype=obj',opt.name,'-o',obj.name],out);assert not run(['nm','-u',obj])
		for cc in ['gcc','clang']:
			exe=out/(stem+'-'+cc);run([cc,'-nostdlib','-static',*(['-no-pie'] if cc=='gcc' else []),assembly,obj,'-o',exe]);assert run([exe])=='';assert not run(['nm','-u',exe]);rows.append(dict(name=exe.name,freestanding=True,status=0,undefined=''))
		(out/(stem+'.machine')).write_text(run(['objdump','-dr',obj]));(out/(stem+'.size')).write_text(run(['size','-A',obj]))
	(out/'results.json').write_text(json.dumps(rows,indent='\t')+'\n');print('24 measured objects and 6 freestanding executions; allocation only from explicit buffers')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve())
