# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Inference diagnostics, context independence, domains and ownership boundaries."""
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
IDENTITY = 'T identity<T>(T x){return x;}'
SAME = 'T same<T>(T a,T b){return a;}'
MAKE = 'T make<T>(){return make<T>();}'
RELAY = 'owned T relay<T>(owned T x) where T : Ownable {return move x;}'
DROP = 'void drop<T>(owned T x) where T : Ownable {}'
CASES = {
	'conflict': (SAME+'void f(){same(1,2.0d);}', "conflicting inferred types for generic parameter 'T': 'int' and 'f64'"),
	'signed-unsigned': (SAME+'void f(i8 a,u8 b){same(a,b);}', "'i8' and 'u8'"),
	'float-width': (SAME+'void f(f32 a,f64 b){same(a,b);}', "'f32' and 'f64'"),
	'literal-no-target': (SAME+'void f(i8 a){same(a,1);}', "'i8' and 'int'"),
	'first-conflict': ('T f<T>(T a,T b,T c){return a;}void root(){f(1,2.0d,true);}', "arguments 1 and 2"),
	'phantom': ('int marker<T>(int x){return x;}void f(){marker(1);}', "cannot infer generic type argument 'T' for 'marker'; write an explicit type argument"),
	'partial-phantom': ('A f<A,B>(A a){return a;}void root(){f(1);}', "cannot infer generic type argument 'B'"),
	'capability-no-candidate': ('int marker<T>() where T : Numeric{return 1;}void f(){marker();}', "cannot infer generic type argument 'T'"),
	'context-local': (MAKE+'void f(){f64 x=make();}', "cannot infer generic type argument 'T'"),
	'context-var': (MAKE+'void f(){var x=make();}', "cannot infer generic type argument 'T'"),
	'context-assignment': (MAKE+'void f(){f64 x=1.0d;x=make();}', "cannot infer generic type argument 'T'"),
	'context-return': (MAKE+'f64 f(){return make();}', "cannot infer generic type argument 'T'"),
	'context-property': (MAKE+'class C{property f64 value{get{return make();}}}', "cannot infer generic type argument 'T'"),
	'context-argument': (MAKE+'void consume(f64 x){}void f(){consume(make());}', "cannot infer generic type argument 'T'"),
	'context-literal': (IDENTITY+'void f(){f64 x=identity(1.25);}', "'f64'"),
	'nested-phantom': (IDENTITY+MAKE+'void f(){identity(make());}', "cannot infer generic type argument 'T'"),
	'capability': ('T f<T>(T a) where T : Numeric{return a;}void root(){f(true);}', "type argument 'bool' does not satisfy capability 'Numeric'"),
	'typed-pointer': (IDENTITY+'void f(int* p){identity(p);}', "GEN-1 type argument 'int*' is unsupported"),
	'slice': (IDENTITY+'void f(int[] p){identity(p);}', "GEN-1 type argument 'int[]' is unsupported"),
	'nominal-conflict': (SAME+'struct S{int value;}struct Q{int value;}void f(){S s={value=1};Q q={value=1};same(s,q);}', "'S' and 'Q'"),
	'plain-resource': (IDENTITY+'void f(Resource x){identity(x);}', "GEN-1 type argument 'Resource' is unsupported"),
	'plain-class': (IDENTITY+'class C{}void f(C x){identity(x);}', "GEN-1 type argument 'C' is unsupported"),
	'plain-owner': (IDENTITY+'void f(){var x=resource(1);identity(x);}', "GEN-1 type argument 'Resource' is unsupported"),
	'plain-buffer': (IDENTITY+'void f(){var x=new int[2];identity(x);}', "GEN-1 type argument 'int[]' is unsupported"),
	'owned-buffer': (DROP+'void f(){var x=new int[2];drop(move x);}', "does not satisfy capability 'Ownable'"),
	'bare-resource': (DROP+'void f(){var x=resource(1);drop(x);}', "requires explicit 'move owner'"),
	'bare-class': (DROP+'class C{init(){}}void f(){var x=C.init();drop(x);}', "requires explicit 'move owner'"),
	'bare-outer-owner': (DROP+'void f<T>(owned T x) where T : Ownable{drop(x);}', "requires explicit 'move owner'"),
	'null-ownable': (DROP+'void f(){drop(null);}', "type argument 'void*' does not satisfy capability 'Ownable'"),
	'owner-conflict': ('void f<T>(owned T a,owned T b) where T : Ownable{}void root(){var a=resource(1);var b=token(2);f(move a,move b);}', "'Resource' and 'Token'"),
	'owner-capability-failure': ('void f<T,U>(owned T a,U b) where T : Ownable where U : Numeric{}void root(){var a=resource(1);f(move a,true);}', "type argument 'bool' does not satisfy capability 'Numeric'"),
	'owner-other-argument': ('void f<T>(owned T a,int b) where T : Ownable{}void root(){var a=resource(1);f(move a,false);}', "argument 2 of function 'f' expects type 'int', provided 'bool'"),
	'outer-owner-other-argument': ('void f<T>(owned T a,int b) where T : Ownable{}void root<T>(owned T a) where T : Ownable{f(move a,false);}', "argument 2 of function 'f' expects type 'int', provided 'bool'"),
	'outer-effect-conflict': (SAME+'bool consume<T>(owned T x) where T : Ownable{return true;}void f<T>(owned T x) where T : Ownable{same(consume(move x),42);}', "'bool' and 'int'"),
	'direct-resource-producer': (DROP+'void f(){drop(resource(1));}', "requires explicit 'move owner'"),
	'direct-native-resource-producer': (DROP+'owned Resource make(){var x=resource(1);return move x;}void f(){drop(make());}', "requires explicit 'move owner'"),
	'direct-class-producer': (DROP+'class C{init(){}}owned C make(){return C.init();}void f(){drop(make());}', "requires explicit 'move owner'"),
	'direct-outer-owned-producer': (DROP+RELAY+'void f<T>(owned T x) where T : Ownable{drop(relay(move x));}', "requires explicit 'move owner'"),
	'probe-double-move': ('U number<T,U>(owned T owner,U value) where T : Ownable{return value;}void f<T>(owned T x) where T : Ownable{var result=number(move x,1.0d)+(1.0+number(move x,2.0d));}', 'use of moved owned value'),
	'borrow-overlap': ('class C{owned Resource r;init(owned Resource r){this.r=move r;}int inspect(){return 1;}}T f<T>(Resource r,T x){return x;}void root(C c){f(c.r,c.inspect());}', 'temporary owned-field borrow overlaps a later containing-object member call'),
	'double-move': (DROP+'void f<T>(owned T x) where T : Ownable{drop(move x);drop(move x);}', 'use of moved owned value'),
	'argument-double-move': ('void sink<T>(owned T a,owned T b) where T : Ownable{}void f<T>(owned T x) where T : Ownable{sink(move x,move x);}', 'use of moved owned value'),
	'outer-conflict': (SAME+'void f<A,B>(A a,B b){same(a,b);}', "'A' and 'B'"),
	'outer-concrete-conflict': (SAME+'void f<T>(T a){same(a,1);}', "'T' and 'int'"),
	'outer-capability': ('T minimum<T>(T a,T b) where T : Ordered{if(a<b){return a;}return b;}T outer<T>(T a,T b){return minimum(a,b);}', "type argument 'T' does not satisfy capability 'Ordered'"),
	'outer-phantom': ('int marker<T,U>(T a){return 1;}int f<T>(T a){return marker(a);}', "cannot infer generic type argument 'U'"),
	'owned-as-plain': (IDENTITY+'void f<T>(owned T x) where T : Ownable{identity(x);}', "GEN-1 type argument 'T' is unsupported"),
	'bounded-generic-borrow': ('void f<T>(borrowed T x,borrowed T y) where T : Ownable{}', 'generic borrowing requires one borrowed T'),
	'nested-pointer': ('T f<T>(T* x){return *x;}', 'type constructors'),
	'constructed-slice': ('struct SliceBox<T>{T value;}int f<T>(SliceBox<T>[] x){return 1;}', 'signature-derived'),
	'constructor-inference': ('struct Box<T>{T value;}void f(){Box x={value=1};}', 'requires explicit type arguments'),
	'arity-missing': (IDENTITY+'void f(){identity();}', "function 'identity' expects 1 arguments, provided 0"),
	'arity-extra': (IDENTITY+'void f(){identity(unknown,2);}', "function 'identity' expects 1 arguments, provided 2"),
	'explicit-partial': ('B pair<A,B>(A a,B b){return b;}void f(){pair<int>(1,2);}', 'expects 2 type arguments, provided 1'),
	'explicit-placeholder': ('B pair<A,B>(A a,B b){return b;}void f(){pair<int,_>(1,2);}', "unknown type '_'"),
	'no-overloads': (IDENTITY+'int identity(int x){return x;}', 'duplicate function'),
}
STAGES = ['semantics','core','instances','cfg','ssa','nabi','cabi','llvm','check']

# GEN-COPY-1 and the approved milestone-15 open-record batch admit these inputs.
SUPERSEDED = {
	'nested-struct': ('struct Box<T>{T value;}int f<T>(Box<T> x){return 1;}', None),
	'struct': (IDENTITY+'struct S{int value;}void f(){S s={value=1};identity(s);}', None),
	'struct-producer': (IDENTITY+'struct S{int value;}S make(){S s={value=1};return s;}void f(){identity(make());}', None),
	'generic-struct': (IDENTITY+'struct Box<T>{T value;}void f(){Box<f64> b={value=1.0d};identity(b);}', None),
}


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	records = []
	for name, (source, message) in (CASES | SUPERSEDED).items():
		path = out/(name+'.astra'); path.write_text(source+'\n')
		for stage in STAGES:
			argv = [str(compiler), '--check' if stage=='check' else '--dump-'+stage, str(path), '--vapi', str(ROOT/'tests/gen-infer/fixtures/runtime.vapi')]
			p = subprocess.run(argv, capture_output=True, text=True)
			if message is None:
				assert p.returncode == 0 and not p.stderr, (name, stage, p)
				(out/(name+'.'+stage)).write_text(p.stdout)
				records.append(dict(name=name,stage=stage,superseded=True))
				continue
			assert p.returncode == 1 and not p.stdout and message in p.stderr, (name, stage, p.returncode, p.stdout, p.stderr, message)
			assert p.stderr.startswith(str(path)+':'), (name, p.stderr)
			if 'conflict' in name or name in ['signed-unsigned','float-width','literal-no-target']:
				assert 'first at '+str(path)+':' in p.stderr, (name,p.stderr)
			if 'capability' in name and name!='capability-no-candidate':
				assert 'cannot infer' not in p.stderr, (name,p.stderr)
			(out/(name+'.'+stage+'.stderr')).write_text(p.stderr)
			records.append(dict(name=name,stage=stage,diagnostic=p.stderr))
	(out/'results.json').write_text(json.dumps(records,indent='\t')+'\n')
	print(f'{len(records)} exact negative-stage checks across {len(CASES)} cases')


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(),Path(sys.argv[2]).resolve())
