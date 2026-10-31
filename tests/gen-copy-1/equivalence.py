# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Byte-exact inferred/explicit stages and stated monomorphic identity mapping."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys
sys.dont_write_bytecode = True

STAGES=['semantics','core','instances','cfg','ssa','nabi','cabi','llvm']


def run(compiler,stage,path):
	p=subprocess.run([compiler,'--dump-'+stage,path.name],cwd=path.parent,capture_output=True,text=True,timeout=30)
	(path.parent/(path.stem+'.'+stage)).write_text(p.stdout)
	(path.parent/(path.stem+'.'+stage+'.stderr')).write_text(p.stderr)
	assert p.returncode==0 and not p.stderr,(path,stage,p)
	return p.stdout


def source(explicit):
	def args(value):
		return '<'+value+'>' if explicit else ''
	return f'''struct A{{int value;f64 gain;}}struct B{{int value;f64 gain;}}struct Single{{int value;}}struct Box<T>{{T value;}}struct OtherBox<T>{{T value;}}struct Phantom<T>{{int tag;}}struct Pair<T,U>{{T first;U second;}}
T id<T>(T x){{return x;}}
T through<T>(T input){{Box<T> first={{value=input}};Box<T> second=first;T saved=second.value;second.value=input;return id{args('T')}(saved);}}
T outer<T>(T input){{Box<T> box={{value=input}};Box<T> copied=id{args('Box<T>')}(box);Box<Box<T>> nested={{value=copied}};Box<Box<T>> saved=id{args('Box<Box<T>>')}(nested);return through{args('T')}(saved.value.value);}}
A produce(A input){{return input;}}
A root(A input){{var named=id{args('A')}(input);var direct=id{args('A')}(produce(named));A[1] records={{direct}};Box<A> box={{value=id{args('A')}(records[0])}};Box<A> saved=id{args('Box<A>')}(box);return outer{args('A')}(saved.value);}}
void aliases(){{Box<int> a={{value=42}};Box<i32> b={{value=42}};Box<i8> c={{value=42}};Box<u8> d={{value=42}};A x={{value=42,gain=3.5d}};B y={{value=42,gain=3.5d}};Phantom<A> p={{tag=1}};Phantom<B> q={{tag=1}};OtherBox<A> o={{value=x}};var aa=id{args('Box<int>')}(a);var bb=id{args('Box<i32>')}(b);var cc=id{args('Box<i8>')}(c);var dd=id{args('Box<u8>')}(d);var xx=id{args('A')}(x);var yy=id{args('B')}(y);var pp=id{args('Phantom<A>')}(p);var qq=id{args('Phantom<B>')}(q);var oo=id{args('OtherBox<A>')}(o);int scalar=id{args('int')}(42);}}
void ordered(){{A a={{value=1,gain=2.0d}};B b={{value=1,gain=2.0d}};Pair<A,B> first={{first=a,second=b}};Pair<B,A> second={{first=b,second=a}};var one=id{args('Pair<A,B>')}(first);var two=id{args('Pair<B,A>')}(second);Single single={{value=42}};var whole=id{args('Single')}(single);int scalar=id{args('int')}(42);}}
'''


def qualify(compiler,out):
	out.mkdir(parents=True,exist_ok=False);rows=[];canonical={}
	for mode in ['explicit','inferred']:
		folder=out/mode;folder.mkdir();path=folder/'input.astra';path.write_text(source(mode=='explicit'))
		for stage in STAGES:
			dump=run(compiler,stage,path)
			if mode=='explicit':canonical[stage]=dump
			else:assert dump==canonical[stage],stage
			rows.append(dict(mode=mode,stage=stage,sha256=hashlib.sha256(dump.encode()).hexdigest()))
	instances=re.findall(r'\(generic-instance #[^\n]+',canonical['instances'])
	keys=[]
	for line in instances:
		key=re.search(r'\(origin #[^)]*\) \(type-arguments [^)]*\)',line)[0];assert key not in keys,key;keys.append(key)
		# Compare one program's exact nominal Kernel functions: only the declared
		# function identity changes. Parameter/local/field ordinals are aligned.
	path=out/'controls.astra'
	body='T selected=second;if(take_first){selected=first;}int i=0;while(i<2){T saved=selected;selected=saved;i=i+1;}return selected;'
	path.write_text('struct Kernel{int index;f64 gain;}T generic<T>(bool take_first,T first,T second){'+body+'}Kernel concrete(bool take_first,Kernel first,Kernel second){'+body.replace('T ','Kernel ')+'}Kernel root(bool take_first,Kernel first,Kernel second){return generic(take_first,first,second);}\n')
	ssa=run(compiler,'ssa',path);llvm=run(compiler,'llvm',path);core=run(compiler,'instances',path)
	functions={name:(ordinal,text) for ordinal,name,text in re.findall(r'\t\(function #(\d+) "([^"]+)"([^\n]*\n[\s\S]*?\n\t\))',ssa)}
	generic_name=next(name for name in functions if name.startswith('astra.gen.'));left=functions['concrete'];right=functions[generic_name]
	assert left[1]==right[1],(left,right)
	llvm_functions={ordinal:body for ordinal,body in re.findall(r'define internal fastcc [^\n]* @astra.fn.(\d+)([\s\S]*?\n})',llvm)}
	assert llvm_functions[left[0]]==llvm_functions[right[0]]
	mapping=dict(functions={'concrete':generic_name},ssa_ordinals={left[0]:right[0]},parameters=['take_first','first.0','first.1','second.0','second.1'],locals={'0':'first','1':'second','2':'selected','3':'i','4':'saved'},fields={'Kernel::index':0,'Kernel::gain':1},comparison='SSA and LLVM complete function bodies; only top-level function identity mapped; no payload, operation, guard, value, predecessor or type-shape rewriting')
	(out/'results.json').write_text(json.dumps(dict(exact_stages=rows,instance_keys=keys,ordinary_mapping=mapping),indent='\t')+'\n')
	print('8 byte-identical explicit/inferred executable stages and exact monomorphic SSA/LLVM bodies')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve())
