# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Definition-time rejection, exact inference conflicts and bounded completion."""
from pathlib import Path
import json
import resource
import subprocess
import sys
sys.dont_write_bytecode = True

ROOT=Path(__file__).resolve().parents[2]
PRELUDE='struct Kernel{int index;f64 gain;}struct Other{int index;f64 gain;}struct Box<T>{T value;}struct Phantom<T>{int tag;}T id<T>(T value){return value;}T same<T>(T a,T b){return a;}\n'
CASES={
	'field-unused':('T bad<T>(T x){return x.index;}','member access'),
	'method-unused':('T bad<T>(T x){return x.method();}','method'),
	'operator-unused':('T bad<T>(T x){return x+x;}','operator'),
	'operator-demanded':('T bad<T>(T x){return x+x;}int main(){return bad(42);}','operator'),
	't-u-copy':('T bad<T,U>(T a,U b){T c=b;return c;}int main(){return bad<int,int>(1,2);}','type'),
	't-u-return':('T bad<T,U>(T a,U b){return b;}','type'),
	'null':('T bad<T>(T a){T x=null;return x;}','null'),
	'uninitialized':('T bad<T>(){T x=x;return x;}','unknown'),
	'uninitialized-record':('Kernel f(){Kernel x=x;return id(x);}','initialized'),
	'parameter-binding':('T bad<T>(T x){x=x;return x;}','parameter'),
	'parameter-field':('void f(Kernel k){k.index=2;}','read-only'),
	'cast':('T bad<T>(T x){return 0 as T;}','cast'),
	'address':('T bad<T>(T x){T local=x;void* p=&local;return x;}','address'),
	'index':('T bad<T>(T x){return x[0];}','index'),
	'pointer-formal':('T bad<T>(T* x){return *x;}','constructors'),
	'slice-owned-formal':('void bad<T>(owned T[] x){T[] escaped=x;}','escaping slice'),
	'fixed-local':('void bad<T>(T x){T[2] a={x,x};}','constructors'),
	'buffer-local':('void bad<T>(T x){var a=new T[2];}','element'),
	'unknown-copy-capability':('T bad<T>(T x) where T:Copy{return x;}','unknown generic capability'),
	'unknown-move-capability':('T bad<T>(T x) where T:Move{return x;}','unknown generic capability'),
	'nominal-conflict':('void f(){Kernel a={index=1,gain=2.0d};Other b={index=1,gain=2.0d};same(a,b);}',"'Kernel' and 'Other'"),
	'symbolic-constructed-conflict':('void f<T,U>(T a,U b){Box<T> x={value=a};Box<U> y={value=b};same(x,y);}',"'Box<T>' and 'Box<U>'"),
	'symbolic-constructed-explicit':('void f<T,U>(T a,U b){Box<T> x={value=a};Box<U> y=id<Box<U>>(x);}','exact nominal'),
	'phantom':('int tag<T>(int n){return n;}void f(){tag(1);}','cannot infer'),
	'phantom-identity':('void f(){Phantom<Kernel> a={tag=1};Phantom<Other> b={tag=1};same(a,b);}','conflicting inferred'),
	'no-result-inference':('T make<T>(){return make<T>();}Kernel f(){return make();}','cannot infer'),
	'eq-after-inference':('bool eq<T>(T a,T b) where T:Eq{return a==b;}void f(){Kernel k={index=1,gain=2.0d};eq(k,k);}',"does not satisfy capability 'Eq'"),
	'ordered-after-inference':('T minimum<T>(T a,T b) where T:Ordered{if(a<b){return a;}return b;}void f(){Kernel k={index=1,gain=2.0d};minimum(k,k);}',"does not satisfy capability 'Ordered'"),
	'numeric-after-inference':('T f<T>(T a) where T:Numeric{return a;}void root(){Kernel k={index=1,gain=2.0d};f(k);}',"does not satisfy capability 'Numeric'"),
	'ownable-record':('void f<T>(owned T x) where T:Ownable{}void root(){Kernel k={index=1,gain=2.0d};f(k);}',"does not satisfy capability 'Ownable'"),
	'owned-disguised':('void f<T>(owned T x) where T:Ownable{Box<T> b={value=x};}','GEN1_PLAIN_COPY'),
	'text':('void f(){id("static text");}','GEN1_PLAIN_COPY'),
	'text-view':('void f(string value){id(value);}','GEN1_PLAIN_COPY'),
	'text-slice':('void f(string[] values){id(values);}','GEN1_PLAIN_COPY'),
	'resource':('void f(R value){id(value);}','GEN1_PLAIN_COPY'),
	'class':('class C{}void f(C value){id(value);}','GEN1_PLAIN_COPY'),
	'pointer':('void f(Kernel* value){id(value);}','GEN1_PLAIN_COPY'),
	'array':('void f(){Kernel[1] a={{index=1,gain=2.0d}};id(a);}','GEN1_PLAIN_COPY'),
	'buffer':('void f(){var a=new Kernel[1];id(a);}','GEN1_PLAIN_COPY'),
	'slice':('void f(Kernel[] values){id(values);}','GEN1_PLAIN_COPY'),
	'box-unsupported':('void f(){Box<string> b={value="text"};}','GEN1_PLAIN_COPY'),
	'initializer-wrong-record':('void f(){Other x={index=1,gain=2.0d};Box<Kernel> b={value=x};}','exact nominal'),
	'initializer-wrong-scalar':('void f(){Box<Kernel> b={value=42};}','StructType Place'),
	'initializer-record-to-scalar':('void f(){Kernel x={index=1,gain=2.0d};Box<int> b={value=x};}','whole-struct'),
	'initializer-missing':('void f(){Box<Kernel> b={};}','missing'),
	'initializer-self':('void f(){Box<Kernel> b={value=b.value};}','unknown'),
	'initializer-duplicate':('void f(){Kernel k={index=1,gain=2.0d};Box<Kernel> b={value=k,value=k};}','duplicate'),
	'empty':('struct Empty{}void f(){Empty x={};id(x);}','empty'),
	'cycle':('struct Cycle{Cycle value;}void f(){Box<Cycle>* p=null;}','recursive'),
	'record-owned-field':('struct Bad{R value;}','field'),
	'record-equality':('void f(){Kernel k={index=1,gain=2.0d};bool b=k==k;}','whole-struct'),
	'record-constant':('const Kernel k=0;','const'),
	'borrow-and-move':('void take<T>(T copy,Kernel[] view,owned Kernel[] owner){}void f(){var a=new Kernel[2];take(a[0],a,move a);}','borrow'),
	'element-after-move':('void take<T>(owned Kernel[] owner,T copy){}void f(){var a=new Kernel[2];take(move a,a[0]);}','moved'),
	'live-destination':('T take<T>(T copy,owned Kernel[] owner){return copy;}void f(){var a=new Kernel[2];a[0]=take(a[1],move a);}','moved'),
	'containing-alias':('class C{owned Kernel[] a;init(){this.a=new Kernel[2];}int replace(){this.a=new Kernel[3];return 0;}}T first<T>(T value,int effect){return value;}void f(C c){C other=c;c.a[0]=first(c.a[1],other.replace());}','overlap'),
}
# Milestone 15: approved open-record batch; original generated source preserved.
# Execution with scalar and copied-record arguments is in structural-generics-15.
SUPERSEDED={
	'constructed-formal':('T bad<T>(Box<T> x){return x.value;}',None),
}
STAGES=['semantics','core','instances','cfg','ssa','nabi','llvm']


def limit():
	resource.setrlimit(resource.RLIMIT_CORE,(0,0))
	resource.setrlimit(resource.RLIMIT_AS,(2*1024**3,2*1024**3))


def qualify(compiler,out):
	out.mkdir(parents=True,exist_ok=False)
	records=[]; failures=[]
	for name,(source,expected) in (CASES | SUPERSEDED).items():
		path=out/(name+'.astra');path.write_text(PRELUDE+source+'\n')
		parsed=subprocess.run([compiler,'--parse',path.name],cwd=out,capture_output=True,text=True,timeout=20)
		assert parsed.returncode==0 and not parsed.stderr,(name,parsed)
		for stage in (['cfg','ssa','nabi','llvm'] if name in ['borrow-and-move','element-after-move','live-destination'] else STAGES):
			p=subprocess.run([compiler,'--dump-'+stage,path.name,'--vapi',ROOT/'tests/struct-elem-1/fixtures/runtime.vapi'],cwd=out,capture_output=True,text=True,timeout=20)
			(out/(name+'.'+stage+'.stderr')).write_text(p.stderr)
			records.append(dict(name=name,stage=stage,status=p.returncode,diagnostic=p.stderr))
			(out/'progress.json').write_text(json.dumps(records,indent='\t')+'\n')
			if expected is None:
				assert p.returncode==0 and not p.stderr,(name,stage,p)
				records[-1]['superseded']=True
				continue
			if not (p.returncode==1 and not p.stdout and expected.lower() in p.stderr.lower() and 'syntax error' not in p.stderr.lower()):
				failures.append((name,stage,expected,p.stderr))
	assert not failures, failures
	for name,call in [('baselib-min','min(k,k)'),('baselib-max','max(k,k)'),('baselib-clamp','clamp(k,k,k)')]:
		path=out/(name+'.astra');path.write_text(PRELUDE+'void f(){Kernel k={index=1,gain=2.0d};'+call+';}\n')
		for stage in STAGES:
			p=subprocess.run([compiler,'--dump-'+stage,path.name,ROOT/'lib/astra/base/order.astra',ROOT/'lib/astra/base/clamp.astra',ROOT/'lib/astra/base/contracts.astra'],cwd=out,capture_output=True,text=True,timeout=20)
			(out/(name+'.'+stage+'.stderr')).write_text(p.stderr)
			assert p.returncode==1 and not p.stdout and "does not satisfy capability 'Ordered'" in p.stderr and 'cannot infer' not in p.stderr,p
			records.append(dict(name=name,stage=stage,status=p.returncode,diagnostic=p.stderr))
	for name,source,expected in [
		('layout','struct Cycle<T>{Cycle<T> value;}void f(Cycle<Kernel>* p){}','recursive generic struct layout'),
		('layout-growth','struct Growing<T>{Growing<Box<T>> value;}void f(Growing<int>* p){}','materialization limit exceeded'),
		('growth','T grow<T>(T input){Box<T> box={value=input};Box<T> copy=grow(box);return input;}int main(){return grow(1);}','materialization limit exceeded'),
		('phantom-growth','T grow<T>(T input){Phantom<T> box={tag=1};Phantom<T> copy=grow(box);return input;}int main(){return grow(1);}','materialization limit exceeded')]:
		path=out/(name+'.astra');path.write_text(PRELUDE+source+'\n')
		for repeat in range(3):
			p=subprocess.run([compiler,'--dump-llvm',path.name],cwd=out,capture_output=True,text=True,timeout=30,preexec_fn=limit)
			(out/(name+f'-{repeat}.stderr')).write_text(p.stderr)
			assert p.returncode==1 and not p.stdout and expected in p.stderr,(name,p)
			records.append(dict(name=name,repeat=repeat,status=p.returncode,diagnostic=p.stderr))
			p=subprocess.run([compiler,'--dump-llvm',FIXTURES/'transport.astra'],capture_output=True,text=True,timeout=20)
			assert p.returncode==0 and not p.stderr,p
	(out/'results.json').write_text(json.dumps(records,indent='\t')+'\n')
	print(f'{len(records)} stage/model completions, including {len(SUPERSEDED)} preserved positive source and subsequent successful compilations')


FIXTURES=ROOT/'tests/gen-copy-1/fixtures'
if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve())
