# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source-authored FLOWSEM expectations, frozen before analyzer implementation."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('ownflow_corpus', ROOT/'tests/selfhost-ownflow/corpus.py')
ownflow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ownflow)
materialize = ownflow.materialize


def cases():
	base = 'class C{init(){}} int use(nonnull C p){return 7;} '
	def nn(name, body, error=None, states=None):
		return dict(name=name, files={'a.astra':base+'int f(C p,bool c){'+body+'}'}, error=error, nulls=states or {}, family='nonnull')
	yield nn('guard', 'if(p!=null){return use({{ready|p}});}return 0;', states={'ready':2})
	yield nn('early', 'if(p==null){return 0;}nonnull C q=p;return use({{ready|q}});', states={'ready':2})
	yield nn('not', 'if(!(p==null)){return use({{ready|p}});}return 0;', states={'ready':2})
	yield nn('and', 'if(p!=null&&use({{ready|p}})==7){return 1;}return 0;', states={'ready':2})
	yield nn('or', 'if(p==null||use({{ready|p}})==7){return 1;}return 0;', states={'ready':2})
	yield dict(name='inferred-fresh-guard', files={'a.astra':base+'int f(nonnull C p,C r){var q=p;q=r;if(q!=null){return use({{ready|q}});}return 0;}'}, error=None, nulls={'ready':2}, family='nonnull')
	yield dict(name='inferred-stale-guard', files={'a.astra':base+'int f(nonnull C p,C r){var q=p;bool prior=q!=null;q=r;if(prior){return use({{error|q}});}return 0;}'}, error='NONNULL_REQUIRED', family='nonnull')
	yield nn('unproved', 'return use({{error|p}});', 'NONNULL_REQUIRED')
	yield nn('join', 'if(p!=null){use(p);}return use({{error|p}});', 'NONNULL_REQUIRED')
	yield nn('overwrite', 'C q=p;if(q!=null){q=null;return use({{error|q}});}return 0;', 'NONNULL_REQUIRED')
	yield nn('stale-bool', 'C q=p;bool prior=q!=null;q=null;if(prior){return use({{error|q}});}return 0;', 'NONNULL_REQUIRED')
	yield nn('loop', 'while(p!=null){return use({{ready|p}});}return 0;', states={'ready':2})
	yield nn('loop-write', 'C q=p;if(q==null){return 0;}while(c){use({{error|q}});q=null;}return 1;', 'NONNULL_REQUIRED')
	yield nn('loop-continue', 'C q=p;while(q!=null){if(c){q=null;continue;}use({{ready|q}});break;}return 0;', states={'ready':2})
	yield nn('zero-trip', 'C q=null;while(c){q=p;}return use({{error|q}});', 'NONNULL_REQUIRED')
	yield nn('parameter', 'nonnull C q=p;return 0;', 'NONNULL_REQUIRED')
	yield dict(name='promise', files={'a.astra':base+'int f(nonnull C p){return use({{ready|p}});}'}, error=None, nulls={'ready':2}, family='nonnull')
	yield dict(name='result', files={'a.astra':base+'owned nonnull C make(){var x=new C();return move x;}int main(){var x=make();return use(x)-7;}'}, error=None, execute=True, family='nonnull')
	yield dict(name='null-result', files={'a.astra':base+'owned nonnull C make(){return null;}'}, error='CHECKED_ERROR', family='nonnull')
	yield dict(name='nullable-result', files={'a.astra':base+'owned C make(){return null;}int main(){var x=make();return use({{error|x}});}'}, error='NONNULL_REQUIRED', family='nonnull')
	for name, body, error in [('owner-null','if(x!=null){return use(x);}return 0;',None), ('moved','var y=move x;return use(x);','MOVED_READ')]:
		yield dict(name=name, files={'a.astra':base+'int f(owned nonnull C x){'+body+'}int main(){var x=new C();return f(move x)-7;}'}, error=error, family='nonnull')
	pair = 'struct Pair{int a;int b;} '
	for name, body, error in [
		('record','Pair p={a={{init_a|3}},b={{init_b|4}}};return {{read_a|p.a}}+{{read_b|p.b}}-7;',None),
		('missing','Pair p={a=3};return 0;','FIELD_INCOMPLETE'),
		('duplicate','Pair p={a=3,a=4};return 0;','FIELD_REPEATED'),
		('replace','Pair p={a=3,b=4};p.a=7;return p.a-7;',None),
	]:
		yield dict(name=name, files={'a.astra':pair+'int main(){'+body+'}'}, error=error, fields={'init_a':16,'init_b':16,'read_a':1,'read_b':1} if name=='record' else {}, family='aggregate', execute=error is None)
	nested = pair+'struct Outer{Pair pair;int tag;} '
	yield dict(name='nested', files={'a.astra':nested+'int main(){Outer o={pair={a=3,b=4},tag=9};return o.pair.a+o.pair.b-7;}'}, error=None, family='aggregate', execute=True)
	yield dict(name='nested-missing', files={'a.astra':nested+'int main(){Outer o={pair={a=3},tag=9};return 0;}'}, error='FIELD_INCOMPLETE', family='aggregate')
	owned = 'struct Packet{owned int[] data;int tag;} '
	for name, body, error in [
		('owned-record','var x=new int[2];Packet p={data={{init_data|move x}},tag=7};return {{read_tag|p.tag}}-7;',None),
		('owned-move','Packet p={data=new int[2],tag=7};var q=move p;return q.tag-7;',None),
		('owned-alias','var x=new int[2];Packet p={data=move x,tag=7};release x;return 0;','INVALID_TRANSFER'),
		('owned-twice','Packet p={data=new int[2],tag=7};var q=move p;var r=move p;return 0;','INVALID_TRANSFER'),
		('owned-stale','Packet p={data=new int[2],tag=7};var q=move p;return p.tag;','MOVED_READ'),
		('owned-replace','Packet p={data=new int[2],tag=7};p.data=new int[3];return len(p.data)-3;','UNSUPPORTED_EFFECT'),
	]:
		yield dict(name=name, files={'a.astra':owned+'int main(){'+body+'}'}, error=None if name=='owned-replace' else error, deferred='UNSUPPORTED_EFFECT' if name=='owned-replace' else None, c0_reject=name=='owned-replace', fields={'init_data':16,'read_tag':1} if name=='owned-record' else {}, family='aggregate', execute=error is None)
	for name, body, error in [
		('ctor','this.a=3;this.b=4;',None),
		('ctor-branch','if(c){this.a=3;}else{this.a=4;}this.b=4;',None),
		('ctor-missing','if(c){this.a=3;}this.b=4;','FIELD_INCOMPLETE'),
		('ctor-return','this.a=3;return;','FIELD_INCOMPLETE'),
		('ctor-loop','while(c){this.a=3;break;}this.b=4;','FIELD_INCOMPLETE'),
		('ctor-read','this.a=this.b;this.b=4;','FIELD_UNINITIALIZED'),
		('ctor-nested','this.pair.a=3;this.pair.b=4;','UNSUPPORTED_EFFECT'),
	]:
		fields = 'Pair pair;' if name=='ctor-nested' else 'int a;int b;'
		yield dict(name=name, files={'a.astra':pair+'class Box{'+fields+'init(bool c){'+body+'}}'}, error=None if name in ('ctor-nested','ctor-return','ctor-loop') else error, deferred='UNSUPPORTED_EFFECT' if name in ('ctor-nested','ctor-return','ctor-loop') else None, c0_reject=name in ('ctor-nested','ctor-return','ctor-loop'), family='aggregate')
	for name, body in [
		('composition','this.child=move x;this.tag=7;'),
		('composition-branch','if(c){this.child=move x;}else{this.child=move y;}this.tag=7;'),
	]:
		yield dict(name=name, files={'a.astra':base+'class Holder{owned nonnull C child;int tag;init(owned nonnull C x,owned nonnull C y,bool c){'+body+'}}int main(){var x=new C();var y=new C();var h=new Holder(move x,move y,true);return h.tag-7;}'}, error=None, family='composition', execute=True)
	yield dict(name='owning-ctor-missing', files={'a.astra':base+'class Holder{owned C child;init(owned C x,bool c){if(c){this.child=move x;}}}'}, error='FIELD_INCOMPLETE', family='aggregate')
	yield dict(name='early-publish', files={'a.astra':'class Box{int a;int b;init(){this.a=observe(this);this.b=7;}}int observe(Box b){return b.a;}'}, error=None, deferred='MEMBER_POLICY', c0_reject=True, family='deferred')
	# These current-C0 families remain explicit frontiers until their own exact
	# member/constructor/foreign-effect contracts have native authority.
	property_base = base+'class Box{owned C child;init(owned C child){this.child=move child;}property borrowed C item{get{return this.child;}}}void effect(){} '
	for name, body, rejects in [
		('property-same','if(a.item!=null){return use(a.item);}return 0;',False),
		('property-other','if(a.item!=null){return use(b.item);}return 0;',True),
		('property-effect','if(a.item!=null){effect();return use(a.item);}return 0;',True),
	]:
		yield dict(name=name, files={'a.astra':property_base+'int f(Box a,Box b){'+body+'}'}, error=None, deferred='MEMBER_POLICY', c0_reject=rejects, family='deferred')
	yield dict(name='generic', files={'a.astra':'struct Wrap<T>{T item;}void f(){Wrap<int> p={item=7};}'}, error=None, deferred='AGGREGATE_20', family='deferred')
