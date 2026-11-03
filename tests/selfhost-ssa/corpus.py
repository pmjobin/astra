# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent source/runtime expectations, declared before SSA implementation."""
PACKET = 'struct Packet{owned int[] data;int tag;}'


def cases():
	def case(name, source, **facts):
		return dict(name='ssa-'+name, source=source, exit=0, facts=facts, core_status=0)
	yield case('straight', 'int main(){int x=2;x=5;x=x+3;return x-8;}', stores=3)
	yield case('diamond', 'int f(bool c){int x=1;if(c){x=7;}else{x=9;}return x;}int main(){return f(true)+f(false)-16;}', place_phi=True)
	yield case('nested-diamond', 'int f(bool a,bool b){int x=0;if(a){if(b){x=2;}else{x=3;}}else{x=5;}return x;}int main(){return f(true,true)+f(true,false)+f(false,true)-10;}', place_phi=True)
	yield case('chain', 'int f(int n){int x=0;if(n==0){x=2;}else{if(n==1){x=4;}else{x=8;}}return x;}int main(){return f(0)+f(1)+f(9)-14;}', place_phi=True)
	yield case('dead-predecessor', 'int f(bool c){int x=4;if(c){return x;}else{x=6;}return x;x=99;}int main(){return f(true)+f(false)-10;}', dead=True)
	yield case('same-literal', 'int f(bool c){int x=0;if(c){x=7;}else{x=7;}return x;}int main(){return f(true)+f(false)-14;}', distinct_equal=True, place_phi=True)
	yield case('and-skip', 'bool fail(int n){return 3/n>0;}int main(){bool b=false&&fail(0);if(b){return 1;}return 0;}', temp_phi=True, skipped=True)
	yield case('or-skip', 'bool fail(int n){return 3/n>0;}int main(){bool b=true||fail(0);if(b){return 0;}return 1;}', temp_phi=True, skipped=True)
	yield case('and-evaluate', 'bool yes(int n){return n==4;}int main(){bool b=true&&yes(4);if(b){return 0;}return 1;}', temp_phi=True)
	yield case('counter', 'int f(int n){int i=0;while(i<n){i=i+1;}return i;}int main(){return f(0)+f(1)+f(5)-6;}', loop_phi=True)
	yield case('nested-continue', 'int f(int n){int i=0;int s=0;while(i<n){i=i+1;int j=0;while(j<3){j=j+1;if(j==2){continue;}s=s+i;}}return s;}int main(){return f(0)+f(1)+f(3)-14;}', loop_phi=True)
	yield case('break-version', 'int f(int n){int x=2;int i=0;while(i<n){i=i+1;x=x+3;if(i==2){break;}}return x;}int main(){return f(0)+f(1)+f(9)-15;}', loop_phi=True)
	yield case('overwrite-join', 'int f(bool c){int x=1;x=2;x=3;if(c){x=x+4;}else{x=x+8;}x=x+1;return x;}int main(){return f(true)+f(false)-20;}', place_phi=True)
	yield case('argument-order', PACKET+'int take(Packet p){return p.tag;}int pair(int a,int b){return a*10+b;}int main(){Packet a={data=new int[2],tag=6};Packet b={data=new int[3],tag=4};return pair(take(move a),take(move b))-64;}', ordered=True, cleanup=True)
	yield case('owning-return', PACKET+'Packet make(int n){Packet p={data=new int[2],tag=n};return move p;}int f(bool c){Packet a=make(4);{Packet b=make(7);if(c){return b.tag+a.tag;}}return a.tag;}int main(){return f(true)+f(false)-15;}', cleanup=True, moves=True)
	yield case('borrow-end', PACKET+'int read(borrowed Packet p){return p.tag;}int take(Packet p){return p.tag;}int main(){Packet p={data=new int[3],tag=5};int n=read(p);return n+take(move p)-10;}', loans=True, moves=True)
	yield case('field-memory', 'struct Pair{int a;int b;}int f(bool c){Pair p={a=2,b=3};if(c){p.a=7;}else{p.b=9;}return p.a+p.b;}int main(){return f(true)+f(false)-21;}', memory=True)
	yield case('separate-functions', 'int one(int x){return x+1;}int two(int x){return x+2;}int main(){return one(3)+two(4)-10;}', functions=3)
