# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent source expectations for opt-in semantic admission."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PAIR = 'struct Pair{int x;int y;}struct Twin{Pair left;Pair right;}'
PACKET = 'struct Packet{owned int[] data;int tag;}'


def cases():
	def case(name, source, family, error=None, diagnostic=None, defer=None, execute=False):
		return dict(name=name, source=source, family=family, error=error, diagnostic=diagnostic, defer=defer, execute=execute)
	for name, body in [
		('nested-initialize', 'Pair p={x=19,y=23};Twin t={left=p,right={x=3,y=4}};p.x=99;return t.left.x+t.left.y-42;'),
		('nested-select', 'Twin t={left={x=19,y=23},right={x=3,y=4}};Pair p=t.left;p.x=8;return t.left.x+t.left.y-42;'),
		('nested-write', 'Twin t={left={x=19,y=23},right={x=3,y=4}};t.right=t.left;return t.right.x+t.right.y-42;'),
		('equal-paths', 'Twin a={left={x=1,y=2},right={x=19,y=23}};Twin b=a;b.left=a.right;a.right.x=0;return b.left.x+b.left.y-42;'),
		('copy-loop', 'Twin a={left={x=19,y=23},right={x=0,y=0}};int i=0;while(i<3){a.right=a.left;i=i+1;}return a.right.x+a.right.y-42;'),
		('copy-branch', 'Pair p={x=19,y=23};Twin a={left=p,right=p};if(p.x==19){a.right=a.left;}else{a.left=a.right;}return a.left.x+a.right.y-42;'),
	]:
		yield case(name, PAIR+'int main(){'+body+'}', 'copy', execute=True)
	yield case('copy-wrong-type', PAIR+'struct Other{int x;int y;}int main(){Other p={x=1,y=2};Twin t={left=p,right={x=0,y=0}};return 0;}', 'copy', 'CHECKED_ERROR', 'type')
	yield case('copy-missing', PAIR+'int main(){Pair p={x=1};Twin t={left=p,right=p};return 0;}', 'copy', 'FIELD_INCOMPLETE', 'missing')
	yield case('copy-owner', PACKET+'int main(){Packet p={data=new int[2],tag=42};Packet q=p;return 0;}', 'copy', 'INVALID_TRANSFER', 'copy')
	yield case('copy-adjacent-owner', PAIR+'struct Mixed{Pair pair;owned int[] data;}int main(){Pair p={x=19,y=23};Mixed m={pair=p,data=new int[3]};Pair q=m.pair;return q.x+q.y-42;}', 'copy', execute=True)
	yield case('nested-channel', 'struct Child{owned int[] left;owned int[] right;int tag;}struct Parent{Child child;int extra;}int read(borrowed Parent p){return p.child.tag+p.extra;}Parent pass(Parent p){return move p;}int main(){Parent p={child={left=new int[2],right=new int[3],tag=40},extra=2};var q=pass(move p);return read(q)-42;}', 'channel', execute=True)
	yield case('copy-owning-member', PACKET+'int main(){Packet p={data=new int[2],tag=42};var q=move p.data;return 0;}', 'copy', defer='UNSUPPORTED_EFFECT')
	for name, source in [
		('channel-consume', 'int take(Packet p){return p.tag;}int main(){Packet p={data=new int[3],tag=42};return take(move p)-42;}'),
		('channel-result', 'Packet make(int n){Packet p={data=new int[3],tag=n};return move p;}int main(){var p=make(42);return p.tag-42;}'),
		('channel-forward', 'Packet pass(Packet p){return move p;}int main(){Packet a={data=new int[2],tag=42};var b=pass(move a);var c=pass(move b);return c.tag-42;}'),
		('channel-borrow', 'int read(borrowed Packet p){return p.tag;}int main(){Packet p={data=new int[3],tag=42};return read(p)+read(p)-84;}'),
		('channel-forward-borrow', 'int read(borrowed Packet p){return p.tag;}int relay(borrowed Packet p){return read(p);}int main(){Packet p={data=new int[3],tag=42};return relay(p)-42;}'),
		('channel-branch', 'int take(Packet p){return p.tag;}int work(bool c){Packet p={data=new int[3],tag=42};if(c){return take(move p);}return p.tag;}int main(){return work(true)+work(false)-84;}'),
		('channel-loop', 'int take(Packet p){return p.tag;}int main(){int i=0;int total=0;while(i<3){Packet p={data=new int[3],tag=14};total=total+take(move p);i=i+1;}return total-42;}'),
	]:
		yield case(name, PACKET+source, 'channel', execute=True)
	for name, source, error, diagnostic in [
		('channel-copy-argument', 'int take(Packet p){return p.tag;}int main(){Packet p={data=new int[3],tag=42};return take(p);}', 'INVALID_TRANSFER', 'explicit move'),
		('channel-duplicate', 'int take(Packet p){return p.tag;}int main(){Packet p={data=new int[3],tag=42};take(move p);return take(move p);}', 'INVALID_TRANSFER', 'moved'),
		('channel-stale', 'int take(Packet p){return p.tag;}int main(){Packet p={data=new int[3],tag=42};take(move p);return p.tag;}', 'MOVED_READ', 'moved'),
		('channel-return-borrow', 'Packet bad(borrowed Packet p){return move p;}int main(){return 0;}', 'INVALID_TRANSFER', 'move'),
		('channel-overlap', 'int both(borrowed Packet a,Packet b){return a.tag+b.tag;}int main(){Packet p={data=new int[3],tag=21};return both(p,move p);}', 'INVALIDATES_ACTIVE_BORROW', 'borrow'),
	]:
		yield case(name, PACKET+source, 'channel', error, diagnostic)
	yield case('channel-unknown', PACKET+'int invoke(Fn<int,Packet> code,Packet p){return code(move p);}', 'channel', defer='UNSUPPORTED_EFFECT')
	yield case('channel-fallible', '[ExceptionRoot]class Error{readonly string text;init(string s){this.text=s;}virtual property string message{get{return this.text;}}}'+PACKET+'Packet make() throws Error{Packet p={data=new int[2],tag=42};return move p;}', 'channel', defer='UNSUPPORTED_EFFECT')
	make=PACKET+'Packet make(){Packet p={data=new int[2],tag=42};return move p;}'
	yield case('discard-owned-result',make+'int main(){make();return 0;}','channel','INVALID_TRANSFER','bounded')
	yield case('explicit-record-release',make+'int main(){var p=make();release p;return 0;}','channel',defer='UNSUPPORTED_EFFECT',diagnostic='release is deferred')
	yield case('discard-copy-result',PAIR+'Pair make(){Pair p={x=19,y=23};return p;}int main(){make();return 0;}','copy','INVALID_TRANSFER','bounded')
	yield case('readonly-record-field','struct Pair{readonly int x;}int main(){Pair p={x=42};return p.x;}','copy',defer='AGGREGATE_20',diagnostic='readonly fields')
	for name, source, diagnostic in [
		('member-read', 'class C{int x;init(){this.x=42;}int read(){return this.x;}}int main(){var c=new C();return c.read()-42;}', None),
		('member-mutates', 'class C{int x;init(){this.x=41;}int read(){this.x=this.x+1;return this.x;}}int main(){var c=new C();return c.read()-42;}', None),
		('member-wrong-receiver', 'struct A{int x;int read(){return this.x;}}struct B{int x;}int main(){B b={x=1};return b.read();}', 'method'),
		('member-null', 'class C{int x;init(){this.x=42;}int read(){return this.x;}}int f(C c){return c.read();}', None),
		('member-readonly', 'struct A{int x;int read(){this.x=this.x+1;return this.x;}}int f(A a){return a.read();}', 'read-only'),
		('property-effect', 'class C{int x;init(){this.x=41;}property int value{get{this.x=this.x+1;return this.x;}}}int main(){var c=new C();return c.value-42;}', None),
	]:
		yield case(name, source, 'member', defer='MEMBER_POLICY', diagnostic=diagnostic, execute=diagnostic is None)
	for name in ('nested', 'deep'):
		path=ROOT/f'tests/struct-copy/fixtures/struct-copy-{name}.astra'
		item=case('existing-'+name, path.read_text(), 'existing', execute=True)
		item['original_path']=str(path)
		yield item
