# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent type expectations; freeze before implementing the checked layer."""
import re


def materialize(files):
	texts, marks = {}, {}
	for path, template in files.items():
		out = bytearray()
		last = 0
		for match in re.finditer(r'\{\{([^|]+)\|([^}]+)\}\}', template):
			out.extend(template[last:match.start()].encode())
			name, text = match.groups()
			assert name not in marks
			start = len(out)
			out.extend(text.encode())
			marks[name] = (path, start, len(out))
			last = match.end()
		out.extend(template[last:].encode())
		texts[path] = bytes(out)
	return texts, marks


def cases():
	def one(name, text, **kw):
		return dict(name=name, files={'a.astra': text}, category='A', **kw)
	for t in ('int', 'i32', 'i8', 'u8', 'i16', 'u16', 'u32', 'i64', 'u64', 'isize', 'usize', 'f32', 'f64', 'bool'):
		yield one('scalar-'+t, t+' f('+t+' {{p|p}}){return {{read|p}};}', types={'p': 'int' if t == 'i32' else t, 'read': 'int' if t == 'i32' else t})
	for name, body, ty in (
		('integer','int x=7;return x;','int'),
		('inference','var x=7;return x;','int'),
		('arithmetic','int x=2; x=(x+3)*4/2%3;return -x;','int'),
		('float','f64 x=1.25;return +x*2.0d;','f64'),
		('boolean','bool x=true; x=!x || false && true;return x & true;','bool'),
		('compare','int x=1;return x<2 && x!=3;','bool'),
		('conditions','int x=1;while(x<3){x=x+1;}if(x==3){return x;}else{return 0;}','int')):
		yield one(name,ty+' f(){'+body+'}')
	yield one('text','bool f(){string {{s|s}}="hi";return {{read|s}}=="hi";}',types={'s':'string','read':'string'})
	yield one('calls','int inc(int x){return x+1;}int f(){var {{v|v}}=inc(3);return {{read|v}};}',types={'v':'int','read':'int'})
	yield one('fn','int code(int x){return x;}int f(){Fn<int,int> {{v|v}}=code;return v(1);}',types={'v':'Fn<int,int>'})
	yield one('callback','int f(borrowed Callback<int,int> {{cb|cb}}){return cb(1);}',types={'cb':'Callback<int,int>'},metadata=[{'name':'cb','kind':7,'flags':2}])
	yield one('inferred-callable','int code(int x){return x;}int f(){Fn<int,int> first=code;var second=first;return second(1);}')
	yield one('competing-callable','int code(int x){return x;}int second(int x){return x+1;}int f(){Fn<int,int> first=code;var second=first;return second(1);}',closed_reason=7)
	yield one('field','struct Pair{int value;}int f(Pair p){return p.{{field|value}};}',closed_reason=1,types={'field':'int'})
	yield one('aggregate','struct Pair{int value;}int f(){Pair p={ {{field|value}}=1};return p.value;}',closed_reason=3,types={'field':'int'})
	yield dict(name='nominal-imports',category='A',files={'a.astra':'namespace A;struct Item{int value;}','b.astra':'namespace B;struct Item{bool value;}','c.astra':'using A;int f(Item a,B.Item b){return a.value;}'})
	yield dict(one('forward-recursive','class Link{Link next;}int f(Link p){return 0;}'), category='C', later='unqualified Class field storage')
	yield one('generic','struct Box<T>{T value;}int f(Box<int> b){return b.value;}')
	yield one('generic-template','T identity<T>(T x){return x;}int f(){return 0;}')
	for name,ty in [('pointer','int*'),('raw','void*'),('slice','int[]'),('vector','i8<16>'),('mask','bool<4>')]:
		yield one(name,'int f('+ty+' {{p|p}}){return 0;}',types={'p':ty})
	yield one('array','int f(){int[4] {{p|data}}={1,2,3,4};return 0;}',types={'p':'int[4]'})
	yield one('slots','class Item{}class Store{owned Item[slots] data;init(){this.data=new Item[slots];}}int f(){return 0;}')
	yield one('nonnull','class Item{int value;}int f(nonnull Item p){return p.value;}',metadata=[{'name':'p','kind':7,'flags':1}])
	yield one('shared','class Item{}int f(borrowed shared Item p){return 0;}')
	yield one('null','int f(int* p){int* q=null;if(q==p){return 1;}return 0;}')
	yield one('fn-channel','class Item{}int f(Fn<owned Item,int> p){return 0;}',callable_result_flags=4)
	yield one('effects','[ExceptionRoot] class Failure{readonly string text;init(string m){this.text=m;}virtual property string message{get{return this.text;}}}int f(owned Failure x) throws Failure{return 0;}',metadata=[{'name':'x','kind':7,'flags':4}],effect_flags=64)
	for name,text in (
		('bad-return','int f(){return {{error|true}};}'),
		('bad-local','int f(){int x={{error|true}};return x;}'),
		('bad-assign','int f(){int x=1;x={{error|false}};return x;}'),
		('bad-if','int f(){if({{error|1}}){return 0;}return 1;}'),
		('bad-while','int f(){while({{error|1}}){}return 1;}'),
		('bad-call-type','int g(int x){return x;}int f(){return g({{error|true}});}'),
		('bad-call-few','int g(int x){return x;}int f(){return {{error|g()}};}'),
		('bad-call-many','int g(int x){return x;}int f(){return {{error|g(1,2)}};}'),
		('bad-fn-call','int f(Fn<int,int> g){return g({{error|true}});}'),
		('bad-binary','int f(){return 1+{{error|true}};}'),
		('bad-width','int f(u32 x){return {{error|x}};}'),
		('bad-unsigned-neg','u32 f(u32 x){return {{error|-x}};}'),
		('bad-float-rem','f32 f(f32 x){return x{{error|%}}2.0f;}'),
		('bad-void','int f({{error|void}} p){return 0;}'),
		('bad-pointer','int f({{error|bool*}} p){return 0;}'),
		('bad-pointer-depth','int f({{error|int**}} p){return 0;}'),
		('bad-vector','int f({{error|int<8>}} p){return 0;}'),
		('bad-array','int f(){ int[{{error|0}}] x={1};return 0;}'),
		('bad-arity','struct Box<T>{T x;}int f({{error|Box<int,bool> }}p){return 0;}'),
		('bad-generic-void','struct Box<T>{T x;}int f(Box<{{error|void}}> p){return 0;}'),
		('bad-nonnull','int f({{error|nonnull int}} p){return 0;}'),
		('bad-shared','int f({{error|shared int}} p){return 0;}'),
		('bad-literal','i8 f(){return {{error|128}};}'),
		('min-negative','int f(){return -2147483648;}'),
		('bad-literal-unsigned','u8 f(){return {{error|-1}};}'),
		('bad-missing-return','int f(){ {{error|return}}; }'),
		('bad-void-return','void f(){return {{error|1}};}'),
		('unknown','int f({{error|Absent}} p){return 0;}'),
		('first-error','int f(){int x={{error|true}};return false;}'),
		('utf8-crlf','// café\r\nint f(){return {{error|true}};}\r\n')):
		item=one(name,text)
		if name!='min-negative': item.update(category='B',error=True)
		yield item
	yield dict(name='nominal-mismatch',category='B',error=True,files={'a.astra':'namespace A;struct Item{int x;}','b.astra':'namespace B;struct Item{int x;}','c.astra':'A.Item f(B.Item x){return {{error|x}};}'})
	yield dict(name='ambiguity',category='B',error=True,files={'a.astra':'namespace A;struct Item{int x;}','b.astra':'namespace B;struct Item{int x;}','c.astra':'using A;using B;int f({{error|Item}} x){return 0;}'})
	yield dict(name='inaccessible',category='B',error=True,files={'a.astra':'namespace A;internal struct Item{int x;}','b.astra':'int f({{error|A.Item}} x){return 0;}'})
	# Additional adversarial families are frozen against C0 before extending
	# these rules. Earlier baseline attempts remain separate runtime evidence.
	yield one('slice-bool','int f(bool[] p){return 0;}')
	yield one('slice-raw','int f(void*[] p){return 0;}')
	yield one('slice-mask','int f(bool<4>[] p){return 0;}')
	yield one('closure-type','class Env{init(){}}int f(borrowed Closure<Env,int,int> p){return 0;}')
	yield one('generic-nested','struct Box<T>{T value;}int f(Box<Box<int>> b){return b.value.value;}')
	yield one('constrained','class Gate<T> where T:Numeric {T value;init(T value){this.value=value;}}int f(Gate<int> p){return 0;}')
	yield one('constant','const int K=2;int f(){return K;}')
	yield one('wide-literals','u64 f(){return 18446744073709551615;}i64 g(){return -9223372036854775808;}')
	yield one('shift','u32 f(u32 x,u8 count){return x<<count;}')
	yield one('conversion','u32 f(int x){return x as u32;}')
	for name,text in (
		('bad-constraint','class Gate<T> where T:Numeric {T value;init(T value){this.value=value;}}int f({{error|Gate<bool> }}p){return 0;}'),
		('bad-generic-pointer','struct Box<T>{ {{error|T*}} value;}int f(){return 0;}'),
		('bad-call-channel','int f(Fn<{{error|owned int}}> p){return 0;}'),
		('bad-owned-scalar','int f({{error|owned int p}}){return p;}'),
		('bad-task','int f({{error|Task}} p){return 0;}'),
		('bad-context','int f({{error|ContextBytes<int> }}p){return 0;}'),
		('bad-mask-pointer','int f({{error|bool<4>*}} p){return 0;}'),
		('bad-shift','int f(int x){return x<<{{error|32}};}'),
		('bad-nominal-field','struct S{int x;}int f(S p){return p.{{error|missing}};}'),
		('type-before-name','int f(){int x={{error|true}};return missing;}'),
		('bad-u64-literal','u64 f(){return {{error|18446744073709551616}};}')):
		yield dict(one(name,text),category='B',error=True)
	yield dict(one('bad-callback-local','int code(int x){return x;}int f(){ {{error|Callback<int,int> cb=code;}} return cb(1);}'),category='B',error=True)
	yield dict(one('bad-owned-result','owned int f(){return 1;}'),category='B',error=True)
	yield dict(one('bad-throws-type','int f() throws int{return 0;}'),category='B',error=True)
	yield dict(one('bad-generic-owner','class Item{}struct Box<T>{T value;}int f(Box<Item> p){return 0;}'),category='B',error=True)
	yield one('nominal-identity','namespace N;struct Item{int x;}struct Other{int x;}int f(Item a,Other b){return 0;}')
	yield one('enum-equality','enum E{A,B}bool f(E a,E b){return a==b;}')
	yield one('inferred-null','int f(){var x=null;return 0;}')
	yield dict(one('bad-void-value','void g(){}int f(){var x={{error|g()}};return 0;}'),category='B',error=True)
	yield dict(one('bad-private-field','class S{private int x;init(){this.x=1;}}int f(S p){return p.{{error|x}};}'),category='B',error=True)
	yield dict(name='generic-canonical',category='A',files={'a.astra':'namespace N;struct Box<T>{T value;}','b.astra':'namespace A;using N;int f(Box<int> {{one|one}}){return one.value;}','c.astra':'namespace B;int g(N.Box<i32> {{two|two}}){return two.value;}'},same=[['one','two']])
	yield one('nonnull-forward','class Item{int value;}int take(nonnull Item p){return p.value;}int f(nonnull Item p){return take(p);}')
	yield one('nonnull-function-address','int code(int x){return x;}int f(){nonnull Fn<int,int> cb=code;return cb(1);}')
	yield dict(one('bad-nonnull-null','class Item{int value;}int f(){nonnull Item p={{error|null}};return 0;}'),category='B',error=True)
	yield dict(one('nonnull-needs-flow','class Item{int value;}int take(nonnull Item p){return p.value;}int f(Item p){return take(p);}'),category='C',later='C0 nonnull control-flow proof',required_deferred=[18])
	yield dict(one('owner-needs-flow','class Item{init(){}}void take(owned Item p){}int f(){var p=new Item();take(p);return 0;}'),category='C',later='C0 owned argument transfer proof',required_deferred=[19])

	yield one('field-metadata','class Record{private readonly string value;init(){this.value="stable";}}int f(){return 0;}',metadata=[{'name':'value','kind':6,'flags':384}])
	yield one('async-metadata','[ExceptionRoot] class Failure{readonly string text;init(string m){this.text=m;}virtual property string message{get{return this.text;}}}enum Status{Completed,Cancelled}async runtime Loop throws Failure returns Status;async int f(){return 0;}',effect_flags=8)
	yield one('foreign-boundary','extern(C) int foreign_value(int value);int f(){return foreign_value(1);}',effect_flags=16,required_deferred=[17])
	yield one('constant-slot-spelling','int f(){const slots=2;int[slots] values={1,2};return 0;}',required_deferred=[11])
	yield one('inherited-field-boundary','class Base{int value;init(int value){this.value=value;}}class Derived:Base{init(int value):base(value){}}int f(Derived p){return p.value;}',required_deferred=[12])
	yield one('local-constant-read','int f(){const int K=3;return K;}')
	yield dict(one('unknown-local-initializer','int f(){int x={{error|missing}};return 0;}'),category='B',error=True)
