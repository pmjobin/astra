# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Definition-time rules, one-layer observations, storage and borrow failures."""
# Approved declaration/inference promotions retain exact originals and
# O0/O1/O2 memory-tested counterparts in structural-generics-15/historical-observations.
from pathlib import Path
import json
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[2]
LIBRARY=ROOT/'lib/astra/base/slices.astra'
PRELUDE='struct Kernel{int index;f64 gain;}struct Other{int index;f64 gain;}struct Box<T>{T value;}struct Phantom<T>{int tag;}struct OtherBox<T>{T value;}T at<T>(T[] a,int i){return a[i];}'
CASES={
	'unused-member':('void bad<T>(T[] a){int x=a[0].index;}','requires an exact StructType Place'),
	'unused-add':('T bad<T>(T[] a){return a[0]+a[0];}','Numeric'),
	'unused-eq':('bool bad<T>(T[] a){return a[0]==a[0];}','Eq'),
	'unused-ordered':('bool bad<T>(T[] a){return a[0]<a[0];}','Ordered'),
	'assign-tu':('void bad<T,U>(T[] a,U[] b){a[0]=b[0];}','expected assignment value'),
	'local-tu':('void bad<T,U>(T[] a,U[] b){T[] view=b;}','initializer'),
	'local-unproved':('void bad<T>(T x){T[] view=x;}','signature-derived'),
	'local-owner':('void bad<T>(T[] a){owned T[] view=a;}','exact owned buffer result'),
	'owned-formal':('void bad<T>(owned T[] a){T[] escaped=a;}','escaping slice'),
	'ownable-element':('void bad<T>(T[] a) where T : Ownable {}','Ownable elements'),
	'plain-ownable':('void bad<T>(T[] a,T x) where T : Ownable {}','Ownable elements'),
	'slice-result':('T[] bad<T>(T[] a){return a;}','slice results'),
	'owned-slice-result':('owned T[] bad<T>(T[] a){return a;}','exact owned buffer result'),
	'constructed-formal':('void bad<T>(Box<T>[] a){}','signature-derived'),
	'array-formal':('void bad<T>(T[2] a){}','type constructors'),
	'pointer-formal':('void bad<T>(T* a){}','type constructors'),
	'vector-formal':('void bad<T>(T<2> a){}','type constructors'),
	'field':('struct Bad<T>{T[] values;}','signature-derived'),
	'allocate':('void bad<T>(T[] a){var values=new T[2];}','unresolved'),
	'null-view':('void bad<T>(T[] a){T[] view=null;}','slice has no null'),
	'raw-view':('void bad<T>(T[] a,void* p){T[] view=p;}','initializer'),
	'parameter-binding':('void bad<T>(T[] a,T[] b){a=b;}','parameter'),
	'infer-local-view':('void bad<T>(T[] a){var saved=a;}','unresolved'),
	'float-index':('void bad<T>(T[] a){T saved=a[1.0];}','IntegerType'),
	'no-numeric-record':('T sum<T>(T[] a,T seed) where T : Numeric{return seed;}void f(Kernel[] a,Kernel k){sum(a,k);}',"capability 'Numeric'"),
	'no-eq-record':('bool same<T>(T[] a,T seed) where T : Eq{return a[0]==seed;}void f(Kernel[] a,Kernel k){same(a,k);}',"capability 'Eq'"),
	'no-numeric-vector':('T sum<T>(T[] a,T seed) where T : Numeric{return seed;}void f(int<2>[] a,int<2> k){sum(a,k);}',"capability 'Numeric'"),
	'literal-f32':('void f(f64[] a){fill(a,1.0);}',"'f64' and 'f32'"),
	'float-conflict':('void f(f64[] a){fill(a,1.0f);}',"'f64' and 'f32'"),
	'small-integer-literal':('void f(i8[] a){fill(a,1);}',"'i8' and 'int'"),
	'first-observation':('void f<T>(T seed,T[] a){}void root(f64[] a){f(1.0,a);}',"'f32' and 'f64'"),
	'multiple-slices':('void f<T>(T[] a,T[] b){}void root(int[] a,f32[] b){f(a,b);}',"'int' and 'f32'"),
	'nominal':('void f<T>(T[] a,T[] b){}void root(Kernel[] a,Other[] b){f(a,b);}',"'Kernel' and 'Other'"),
	'generic-definition':('void f<T>(T[] a,T[] b){}void root(Box<Kernel>[] a,OtherBox<Kernel>[] b){f(a,b);}',"'Box<Kernel>' and 'OtherBox<Kernel>'"),
	'phantom-identity':('void f<T>(T[] a,T[] b){}void root(Phantom<Kernel>[] a,Phantom<Other>[] b){f(a,b);}',"'Phantom<Kernel>' and 'Phantom<Other>'"),
	'phantom-parameter':('void f<T,U>(T[] a){}void root(int[] a){f(a);}',"cannot infer generic type argument 'U'"),
	'partial-type-list':('void f<T,U>(T[] a,U u){}void root(int[] a){f<int>(a,1);}','full ordered list'),
	'whole-slice':('T identity<T>(T a){return a;}void f(int[] a){identity(a);}',"type argument 'int[]' is unsupported"),
	'string-pattern':('void f(string[] a){fill(a,"x");}',"type argument 'string' is unsupported"),
	'unused-string':('void ignore<T>(T[] a){}void f(string[] a){ignore(a);}',"type argument 'string' is unsupported"),
	'array-decay':('void f(){int[2] a={1,2};fill(a,1);}','whole-array'),
	'not-view':('void f(){fill(1,1);}','exact slice view'),
	'borrow-move':('void f<T>(T[] view,owned Kernel[] owner){}void root(){var a=new Kernel[2];f(a,move a);}','cannot borrow moved'),
	'borrow-nested-move':('int drop(owned Kernel[] a){return 1;}void f<T>(T[] view,int n){}void root(){var a=new Kernel[2];f(a,drop(move a));}','cannot borrow moved'),
	'live-destination':('Kernel drop(owned Kernel[] a){Kernel k={index=1,gain=1.0d};return k;}void root(){var a=new Kernel[2];a[0]=drop(move a);}','cannot borrow moved'),
	'field-later-replace':('class Owner{owned Kernel[] a;init(){this.a=new Kernel[2];}int replace(){this.a=new Kernel[3];return 0;}}void root(Owner owner){swap_elements(owner.a,0,owner.replace());}','temporary owned-field borrow overlaps'),
	'field-alias-owner':('class Owner{owned Kernel[] a;init(){this.a=new Kernel[2];}}void f<T>(T[] a,Owner b){}void root(Owner a,Owner b){f(a.a,b);}','temporary owned-field borrow overlaps'),
	'destination-field-replace':('class Owner{owned Kernel[] a;init(){this.a=new Kernel[2];}Kernel replace(){this.a=new Kernel[3];Kernel k={index=1,gain=1.0d};return k;}}void root(Owner owner){owner.a[0]=owner.replace();}','temporary owned-field borrow overlaps'),
	'local-escape':('void f<T>(T[] a){T[] outer=a;{int[1] inner={1};outer=slice(inner);}}','assignment'),
	'duplicate-library':('void fill<T>(T[] a,T x){}','duplicate function'),
}
SYNTAX={
	'nested-slice':'void f<T>(T[][] a){}',
	'missing-initializer':'void f<T>(T[] a){T[] view;}',
}
STAGES=['semantics','core','instances','cfg','ssa','nabi','llvm']


def qualify(compiler,out):
	out.mkdir(parents=True,exist_ok=False);records=[];failures=[]
	for name,(text,expected) in CASES.items():
		path=out/(name+'.astra');path.write_text(PRELUDE+text+'\n')
		parsed=subprocess.run([compiler,'--parse',path.name],cwd=out,capture_output=True,text=True)
		assert parsed.returncode==0 and not parsed.stderr,(name,parsed)
		for stage in (['cfg','ssa','nabi','llvm'] if name in ['borrow-move','borrow-nested-move','live-destination'] else STAGES):
			p=subprocess.run([compiler,'--dump-'+stage,LIBRARY,path.name],cwd=out,capture_output=True,text=True,timeout=30)
			(out/(name+'.'+stage+'.stderr')).write_text(p.stderr)
			records.append(dict(name=name,stage=stage,status=p.returncode,diagnostic=p.stderr))
			if not (p.returncode==1 and not p.stdout and expected.lower() in p.stderr.lower() and 'syntax error' not in p.stderr.lower()):
				failures.append((name,stage,expected,p.stderr))
	for name,text in SYNTAX.items():
		path=out/(name+'.astra');path.write_text(text+'\n')
		p=subprocess.run([compiler,'--parse',path.name],cwd=out,capture_output=True,text=True)
		assert p.returncode==1 and not p.stdout,(name,p)
		records.append(dict(name=name,stage='syntax',status=p.returncode,diagnostic=p.stderr))
	(out/'results.json').write_text(json.dumps(records,indent='\t')+'\n')
	assert not failures,failures
	print(f'{len(records)} stage-qualified rejections')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve())
