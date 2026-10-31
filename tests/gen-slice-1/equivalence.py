# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact application identity and independently written monomorphic bodies."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[2]
LIBRARY=ROOT/'lib/astra/base/slices.astra'
STAGES=['semantics','core','instances','cfg','ssa','nabi','cabi','llvm']


def run(compiler,stage,path):
	p=subprocess.run([compiler,'--dump-'+stage,LIBRARY,path.name],cwd=path.parent,capture_output=True,text=True,timeout=30)
	(path.parent/(path.stem+'.'+stage)).write_text(p.stdout);(path.parent/(path.stem+'.'+stage+'.stderr')).write_text(p.stderr)
	assert p.returncode==0 and not p.stderr,(path,stage,p)
	return p.stdout


def source(explicit):
	def args(value):
		return '<'+value+'>' if explicit else ''
	return f'''struct A{{int x;f64 y;}}struct B{{int x;f64 y;}}struct Box<T>{{T value;}}struct OtherBox<T>{{T value;}}struct Phantom<T>{{int tag;}}
T at<T>(T[] values,int index){{return values[index];}}
T identity<T>(T x){{return x;}}
T outer<T>(T[] first,T[] second,T seed){{T[] alias=first;T[] saved=alias;alias=second;fill{args('T')}(saved,seed);T value=at{args('T')}(alias,0);return identity{args('T')}(value);}}
void root(A[] aa,B[] bb,Box<A>[] boxes,Box<int>[] ints,Box<i32>[] aliases,Phantom<A>[] p,Phantom<B>[] q,OtherBox<A>[] others,A a,B b,Box<A> box,Box<int> number,Phantom<A> pp,Phantom<B> qq,OtherBox<A> other){{
fill{args('A')}(aa,a);fill{args('B')}(bb,b);fill{args('Box<A>')}(boxes,box);fill{args('Box<int>')}(ints,number);fill{args('Box<i32>')}(aliases,number);fill{args('Phantom<A>')}(p,pp);fill{args('Phantom<B>')}(q,qq);fill{args('OtherBox<A>')}(others,other);
A[2] fixed={{a,a}};fill{args('A')}(slice(fixed),a);var buffer=new A[2];fill{args('A')}(buffer,at{args('A')}(aa,0));swap_elements{args('A')}(buffer,0,1);var saved=outer{args('A')}(buffer,aa,a);
}}
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
	instances=re.findall(r'\(generic-instance #[^\n]+',canonical['instances']);keys=[]
	for line in instances:
		key=re.search(r'\(origin #[^)]*\) \(type-arguments [^)]*\)',line)[0];assert key not in keys,key;keys.append(key)
	path=out/'controls.astra'
	path.write_text('''struct Kernel{int index;f64 gain;}
void numeric(int[] values,int value){var index=0;while(index<len(values)){values[index]=value;index=index+1;}}
void records(Kernel[] values,Kernel value){var index=0;while(index<len(values)){values[index]=value;index=index+1;}}
Kernel record_at(Kernel[] values,int index){return values[index];}
int numeric_at(int[] values,int index){return values[index];}
void numeric_swap(int[] values,int first,int second){int left=values[first];int right=values[second];values[first]=right;values[second]=left;}
void record_swap(Kernel[] values,int first,int second){Kernel left=values[first];Kernel right=values[second];values[first]=right;values[second]=left;}
T at<T>(T[] values,int index){return values[index];}
void root(int[] integers,Kernel[] kernels,Kernel value){fill(integers,1);fill(kernels,value);var saved=at(kernels,0);var number=at(integers,0);swap_elements(integers,0,1);swap_elements(kernels,0,1);}
''')
	ssa=run(compiler,'ssa',path);llvm=run(compiler,'llvm',path);inventory=run(compiler,'instances',path)
	functions={name:(ordinal,text) for ordinal,name,text in re.findall(r'\t\(function #(\d+) "([^"]+)"([^\n]*\n[\s\S]*?\n\t\))',ssa)}
	llvm_functions={ordinal:body for ordinal,body in re.findall(r'define internal fastcc [^\n]* @astra.fn.(\d+)([\s\S]*?\n})',llvm)}
	mapping=[]
	for ordinary,origin,element in [('numeric','fill','int'),('records','fill','Kernel'),('record_at','at','Kernel'),('numeric_at','at','int'),('numeric_swap','swap_elements','int'),('record_swap','swap_elements','Kernel')]:
		line=next(line for line in inventory.splitlines() if '(generic-instance #' in line and f'"{origin}") (type-arguments {element})' in line)
		name='astra.gen.'+re.search(r'\(origin #(\d+)',line)[1]+'.'+re.search(r'\(generic-instance #(\d+)',line)[1]
		left,right=functions[ordinary],functions[name]
		assert left[1]==right[1],(ordinary,name,'SSA')
		assert llvm_functions[left[0]]==llvm_functions[right[0]],(ordinary,name,'LLVM')
		mapping.append(dict(ordinary=ordinary,specialized=name,ordinals=[left[0],right[0]],comparison='Complete SSA/LLVM bodies; only top-level function identities differ; no guard, shape, metadata, payload or instruction normalization.'))
	control=out/'concrete-requests.astra';control.write_text('struct Box<T>{T value;}void first(Box<int>[] a){var x=a[0];var y=a[0];}void second(Box<int>[] b){var z=b[0];}\n')
	requests=run(compiler,'instances',control)
	assert '(state COMPLETE) (requests 7)' in requests,requests
	(out/'results.json').write_text(json.dumps(dict(exact_stages=rows,instance_keys=keys,ordinary_mapping=mapping),indent='\t')+'\n')
	print('8 byte-identical explicit/inferred stages; 6 complete monomorphic SSA/LLVM bodies')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve())
