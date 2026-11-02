# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent source expectations; freeze records C0 before native comparison."""
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
	prefix = 'void see(int[] p){} void take(owned int[] p){} '
	def buffer(name, body, error=None, states=None):
		return dict(name=name, files={'a.astra':prefix+'void f(owned int[] x,bool c){'+' '+body+'}'}, error=error, states=states or {})
	yield buffer('read', 'see({{read|x}});', states={'read':1})
	yield buffer('move', 'var next=move x;see({{read|next}});', states={'read':1})
	yield buffer('move-twice', 'var next=move x;var other={{error|move x}};', 'INVALID_TRANSFER')
	yield buffer('release-twice', 'release x;{{error|release x;}}', 'DOUBLE_RELEASE')
	yield buffer('release-after-move', 'var next=move x;{{error|release x;}}', 'INVALID_TRANSFER')
	yield buffer('read-after-release', 'release x;see({{error|x}});', 'RELEASED_READ')
	yield buffer('read-after-move', 'take(move x);see({{error|x}});', 'MOVED_READ')
	yield buffer('one-arm', 'if(c){take(move x);}see({{error|x}});', 'MAYBE_MOVED_READ', {'error':3})
	yield buffer('two-arms', 'if(c){take(move x);}else{take(move x);}see({{error|x}});', 'MOVED_READ', {'error':2})
	yield buffer('release-arm', 'if(c){release x;}see({{error|x}});', 'MAYBE_MOVED_READ', {'error':5})
	yield buffer('rearm', 'release x;x=new int[2];see({{read|x}});', states={'read':1})
	yield buffer('replace-owned', 'x=new int[2];see({{read|x}});', states={'read':1})
	yield buffer('rearm-join', 'if(c){take(move x);}x=new int[2];see({{read|x}});', states={'read':1})
	yield buffer('self-rearm', 'x={{error|move x}};', 'INVALID_TRANSFER')
	yield buffer('loop-carried', 'while(c){see({{error|x}});take(move x);}', 'MAYBE_MOVED_READ', {'error':3})
	yield buffer('loop-rearm', 'while(c){take(move x);x=new int[2];}see({{read|x}});', states={'read':1})
	yield buffer('loop-join', 'while(c){take(move x);break;}see({{error|x}});', 'MAYBE_MOVED_READ', {'error':3})
	yield buffer('loop-local', 'while(c){var y=new int[2];take(move y);}see({{read|x}});', states={'read':1})
	yield buffer('continue', 'while(c){take(move x);continue;}see(x);', 'INVALID_TRANSFER')
	yield buffer('continue-rearm', 'while(c){take(move x);x=new int[2];continue;}see({{read|x}});', states={'read':1})
	yield buffer('for-carried', 'for(int i=0;i<3;i=i+1){see({{error|x}});take(move x);}', 'MAYBE_MOVED_READ', {'error':3})
	yield buffer('for-rearm', 'for(int i=0;i<3;i=i+1){take(move x);x=new int[2];}see({{read|x}});', states={'read':1})
	yield buffer('for-continue', 'for(int i=0;i<3;i=i+1){take(move x);x=new int[2];continue;}see({{read|x}});', states={'read':1})
	yield buffer('nested-exits', 'while(c){while(c){if(c){break;}continue;}take(move x);return;}see({{read|x}});', states={'read':1})
	yield buffer('early-return', 'if(c){take(move x);return;}see({{read|x}});', states={'read':1})
	yield buffer('unreachable', 'take(move x);return;see(x);release x;')
	yield buffer('constant-false', 'while(false){take({{error|move x}});}see({{read|x}});', 'INVALID_TRANSFER', {'read':3})
	yield buffer('constant-true', 'while(true){take(move x);return;}see(x);')
	yield buffer('sibling-names', '{var y=new int[2];take(move y);}{var y=new int[1];see(y);}see({{read|x}});', states={'read':1})
	yield buffer('owned-copy', 'owned int[] y={{error|x}};', 'INVALID_TRANSFER')
	yield buffer('stored-view', 'int[] y={{error|x}};', 'BORROW_ESCAPE')
	yield buffer('owner-to-borrow-then-move', 'see(x);take(move x);')
	for name, args, error in [('call-loan','x,move x','INVALIDATES_ACTIVE_BORROW'),('call-distinct','x,move y',None),('call-aliases','x,x',None)]:
		decl='void both(int[] a,'+('int[] b' if name=='call-aliases' else 'owned int[] b')+'){} '
		yield dict(name=name, files={'a.astra':decl+'void f(owned int[] x,owned int[] y){both('+args+');}'}, error=error)
	yield dict(name='late-loan',files={'a.astra':'int use(owned int[] a,int[] b){return 0;}void f(owned int[] x){use(move x,x);}'},error='INVALIDATES_ACTIVE_BORROW')
	yield dict(name='duplicate-call-transfer',files={'a.astra':'void use(owned int[] a,owned int[] b){}void f(owned int[] x){use(move x,move x);}'},error='INVALID_TRANSFER')
	yield dict(name='return-owner',files={'a.astra':'owned int[] f(owned int[] x){return move x;}'},error=None)
	yield dict(name='return-moved',files={'a.astra':'owned int[] f(owned int[] x){var y=move x;return {{error|move x}};}'},error='INVALID_TRANSFER')
	yield dict(name='return-copy',files={'a.astra':'owned int[] f(owned int[] x){return {{error|x}};}'},error='INVALID_TRANSFER')
	for name,body,error in [
		('pointer','int x=1;int* p=&x;{int* q=p;}',None),
		('pointer-null','int* p=null;{int* q=p;}',None),
		('pointer-store-escape','int* out=null;{int x=1;out={{error|&x}};}','BORROW_ESCAPE'),
		('pointer-copy-escape','int x=1;int* out=&x;{int* inner=out;out={{error|inner}};}','BORROW_ESCAPE'),
		('pointer-safe-inner','int x=1;int* out=&x;{int* inner=null;inner=out;}',None),
		('pointer-loop-escape','int* out=null;while(false){int x=1;out={{error|&x}};}','BORROW_ESCAPE'),
	]:
		yield dict(name=name,files={'a.astra':'void f(){'+' '+body+'}'},error=error)
	for name,body,error in [
		('class-owner','var x=new Item();see(x);take(move x);',None),
		('class-release','var x=new Item();release x;',None),
		('class-double-release','var x=new Item();release x;{{error|release x;}}','DOUBLE_RELEASE'),
		('class-local-move','var x=new Item();var y=move x;see(y);',None),
		('class-stored-owner','var x=new Item();Item y={{error|x}};','BORROW_ESCAPE'),
		('class-alias','Item a=null;Item b=a;{Item c=b;}',None),
		('class-copy-escape','Item a=null;{Item b=a;a={{error|b}};}','BORROW_ESCAPE'),
		('null-result','var x=empty();see(x);take(move x);',None),
	]:
		yield dict(name=name,files={'a.astra':'class Item{init(){}}void see(Item p){}void take(owned Item p){}owned Item empty(){return null;}void f(){'+' '+body+'}'},error=error)
	yield dict(name='class-call-loan',files={'a.astra':'class Item{init(){}}void both(Item a,owned Item b){}void f(){var x=new Item();both(x,move x);}'},error='INVALIDATES_ACTIVE_BORROW')
	yield dict(name='shortcircuit',files={'a.astra':'bool take(owned int[] x){return true;}void f(owned int[] x,bool c){if(c&&take(move x)){}int[] view={{error|x}};}'},error='BORROW_ESCAPE')
	yield dict(name='shortcircuit-state',files={'a.astra':'bool take(owned int[] x){return true;}void see(int[] x){}void f(owned int[] x,bool c){if(c&&take(move x)){}see({{error|x}});}'},error='MAYBE_MOVED_READ',states={'error':3})
	yield dict(name='multi-source',files={'a.astra':'namespace A;void use(owned int[] x){release x;}','b.astra':'namespace B;void use(owned int[] x){release x;}','c.astra':'using A;void f(){var x=new int[2];A.use(move x);var y=new int[2];B.use(move y);}'},error=None)
	# Separate named frontiers: these must never encode a proved result.
	for name,text,reason in [
		('defer-foreign','extern(C) int foreign_value();int f(){return foreign_value();}','FOREIGN_CALL'),
		('defer-nonnull','class C{init(){}}void use(nonnull C p){}void f(C p){use(p);}','NONNULL_18'),
		('defer-aggregate','struct Pair{int x;}void f(){Pair x={x=1};}','AGGREGATE_20'),
		('defer-pointer-result','int* f(){return null;}','RESULT_LIFETIME'),
		('defer-generic','void f<T>(owned T x){}','GENERIC_POLICY'),
	]:
		yield dict(name=name,files={'a.astra':text},error=None,deferred=reason,c0_reject=name in ('defer-nonnull','defer-pointer-result','defer-generic'))
		# Meaningful executable behavior, zero/one/many iterations and null owners.
	yield dict(name='runtime-loop',files={'a.astra':'void take(owned int[] x){}int run(int n){var x=new int[1];int i=0;while(i<n){take(move x);x=new int[1];i=i+1;}return i;}int main(){if(run(0)!=0||run(1)!=1||run(5)!=5){return 1;}return 0;}'},error=None,execute=True)
	yield dict(name='runtime-pointer',files={'a.astra':'int main(){int x=3;int* p=&x;{int* q=p;*q=7;}if(x!=7){return 1;}return 0;}'},error=None,execute=True)

	# Added from independent full-C0 origin/noescape probes, before this adapter runs.
	yield dict(name='class-heap-parameter-release',files={'a.astra':'class Item{init(){}}void f(owned Item {{heap_param|x}}){release x;}int main(){var x=new Item();f(move x);return 0;}'},error=None,execute=True,origins={'heap_param':2})
	yield dict(name='class-heap-return',files={'a.astra':'class Item{init(){}}owned Item f(){var x=new Item();return move x;}int main(){var {{heap_owner|x}}=f();release x;return 0;}'},error=None,execute=True,origins={'heap_owner':2})
	yield dict(name='class-unrooted-release',files={'a.astra':'class Item{init(){}}void f(owned Item x){release x;}'},error=None,deferred='CLASS_RELEASE_ORIGIN',c0_reject=True)
	yield dict(name='class-null-release',files={'a.astra':'class Item{init(){}}owned Item f(){return null;}void g(){var {{null_owner|x}}=f();release x;}'},error=None,deferred='CLASS_RELEASE_ORIGIN',c0_reject=True,origins={'null_owner':1})
	yield dict(name='class-mixed-origin',files={'a.astra':'class Item{init(){}}void f(owned Item x){}int main(){var x=new Item();f(move x);owned Item y=Item.init();f(move y);return 0;}'},error=None,deferred='CLASS_ORIGIN_POLICY',c0_reject=True)
	yield dict(name='raw-borrow-forward',files={'a.astra':'bool same(borrowed void* p){return p==null;}bool f(borrowed void* p){return same(p);}'},error=None)
	yield dict(name='raw-borrow-store',files={'a.astra':'void f(borrowed void* p){void* q={{error|p}};}'},error='BORROW_ESCAPE')
	yield dict(name='raw-borrow-unmanaged',files={'a.astra':'void raw(void* p){}void f(borrowed void* p){raw({{error|p}});}'},error='BORROW_ESCAPE')
	yield dict(name='borrowed-scalar-pointer',files={'a.astra':'void f(borrowed int* p){}'},error=None,deferred='BORROW_CHANNEL_POLICY',c0_reject=True)
	yield dict(name='negative-buffer-count',files={'a.astra':'void f(){var x=new int[-1];}'},error=None,deferred='BUFFER_COUNT_POLICY',c0_reject=True)
	failure='[ExceptionRoot] class Failure{readonly string text;init(string m){this.text=m;}virtual property string message{get{return this.text;}}}'
	yield dict(name='fallible-call',files={'a.astra':failure+'void take(owned int[] x) throws Failure{}void f(owned int[] x) throws Failure{take(move x);}'},error=None,deferred='UNSUPPORTED_EFFECT')

	yield dict(name='class-null-heap-parameter',files={'a.astra':'class Item{init(){}}void f(owned Item {{nullable_owner|x}}){release x;}int main(){var x=new Item();f(move x);f(null);return 0;}'},error=None,execute=True,origins={'nullable_owner':3})
	yield dict(name='class-null-call-loan',files={'a.astra':'class Item{init(){}}owned Item empty(){return null;}void both(Item a,owned Item b){}void f(){var x=empty();both(x,{{error|move x}});}'},error='INVALIDATES_ACTIVE_BORROW')

	yield dict(name='buffer-index-copy',files={'a.astra':'int main(){var x=new int[2];x[0]=7;int n=x[0];release x;return n-7;}'},error=None,execute=True)
	yield dict(name='buffer-index-moved',files={'a.astra':'void take(owned int[] p){}int f(owned int[] x){take(move x);return {{error|x}}[0];}'},error='MOVED_READ')

	yield dict(name='address-bool',files={'a.astra':'void f(){bool x=true;var p=&x;}'},error=None,deferred='BORROW_CHANNEL_POLICY',c0_reject=True)
	yield dict(name='address-parameter',files={'a.astra':'void f(int x){var p=&x;}'},error=None,deferred='BORROW_CHANNEL_POLICY',c0_reject=True)

	# Independent source admission boundaries; these are not ownership proofs.
	for name,text,reason,reject in [
		('constant-local-effect','int effect(){return 1;}void f(){const int K=effect();}','CONSTANT_VALUE_POLICY',True),
		('constant-global-effect','int effect(){return 1;}const int K=effect();','CONSTANT_VALUE_POLICY',True),
		('return-fallthrough','int f(bool c){if(c){return 1;}}','RETURN_COMPLETENESS',True),
		('text-parameter','void f(string p){}','TEXT_LIFETIME_POLICY',False),
	]:
		yield dict(name=name,files={'a.astra':text},error=None,deferred=reason,c0_reject=reject)
	yield dict(name='nested-scalar-context',files={'a.astra':'int main(){u32 scalar=128;var x=new u8[1];x[0]=(192|(scalar>>6)) as u8;int n=x[0] as int;release x;return n-194;}'},error=None,execute=True)

	yield dict(name='class-typed-move',files={'a.astra':'class Item{init(){}}void f(){var x=new Item();owned Item y=move x;}'},error=None)

	# C0 keeps copied parameter views rooted in their exact local storage.
	yield dict(name='buffer-param-copy',files={'a.astra':'void f(int[] x){int[] y=x;}'},error=None)
	yield dict(name='class-param-copy',files={'a.astra':'class Item{init(){}}void f(Item x){Item y=x;}'},error=None)
	yield dict(name='buffer-param-escape',files={'a.astra':'void f(int[] x){int[] out=x;{int[] inner=out;out={{error|inner}};}}'},error='BORROW_ESCAPE')
	yield dict(name='pointer-param-copy',files={'a.astra':'void f(int* p){int* q=p;}'},error=None)

	yield dict(name='foreign-member-policy',files={'a.astra':'class Item{[Foreign]init(){}}void f(){var x=new Item();release x;}'},error=None,deferred='TYPE_POLICY',c0_reject=True)
