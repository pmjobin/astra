# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source-level expectations authored before CFG implementation."""
PACKET = 'struct Packet{owned int[] data;int tag;}'


def cases():
	def case(name, source, result=0, **facts):
		return dict(name=name, source=source, exit=result, facts=facts)
	yield case('nested-choice', 'int f(int n){if(n<0){return 3;}else{if(n==0){return 7;}else{return 11;}}}int main(){return f(-1)+f(0)+f(2)-21;}', returns=4, branches=2)
	yield case('zero-one-many', 'int f(int n){int i=0;int s=0;while(i<n){i=i+1;s=s+i;}return s;}int main(){return f(0)+f(1)+f(4)-11;}', loops=1)
	yield case('taken-continue', 'int f(int n){int i=0;int s=0;while(i<n){i=i+1;if(i==2){continue;}s=s+i;}return s;}int main(){return f(1)+f(4)-9;}', loops=1, continues=1)
	yield case('taken-break', 'int add(int a,int b){return a+b;}int work(int n){int i=0;int total=0;while(i<n){i=i+1;if(i==2){continue;}if(i>5){break;}total=add(total,i);}return total;}int main(){return work(0)+work(1)+work(3)+work(7)-18;}', loops=1, breaks=1, continues=1)
	yield case('nested-loops', 'int f(int n){int i=0;int s=0;while(i<n){i=i+1;int j=0;while(j<4){j=j+1;if(j==2){continue;}if(j==4){break;}s=s+1;}if(i==3){break;}}return s;}int main(){return f(0)+f(1)+f(5)-8;}', loops=2, breaks=2, continues=1)
	yield case('nested-early-return', 'int f(int n){int i=0;while(i<n){i=i+1;int j=0;while(j<3){j=j+1;if(i==2){if(j==2){return 9;}}}}return 4;}int main(){return f(0)+f(1)+f(3)-17;}', loops=2, returns=3)
	yield case('short-skip', 'bool die(int n){return 1/n>0;}int main(){if(false&&die(0)){return 1;}if(true||die(0)){return 0;}return 2;}', short=2, calls=2)
	yield case('short-evaluate', 'bool yes(int n){return n==7;}int main(){if(true&&yes(7)){if(false||yes(7)){return 0;}}return 1;}', short=2, calls=2)
	yield case('short-fatal-and', 'bool die(int n){return 1/n>0;}int main(){if(true&&die(0)){return 1;}return 0;}', 132, short=1, fatal_signal=4)
	yield case('short-fatal-or', 'bool die(int n){return 1/n>0;}int main(){if(false||die(0)){return 1;}return 0;}', 132, short=1, fatal_signal=4)
	yield case('owner-loop-exits', PACKET+'int f(int n){int i=0;int s=0;while(i<n){Packet p={data=new int[2],tag=3};i=i+1;{Packet q={data=new int[3],tag=4};if(i==2){continue;}if(i==4){break;}s=s+q.tag;}s=s+p.tag;}return s;}int main(){return f(0)+f(1)+f(5)-21;}', loops=1, breaks=1, continues=1, cleanup=True)
	yield case('owner-conditional-return', PACKET+'int take(Packet p){return p.tag;}int f(bool c){Packet a={data=new int[2],tag=5};{Packet b={data=new int[3],tag=7};if(c){return take(move b)+a.tag;}return b.tag+a.tag;}}int main(){return f(true)+f(false)-24;}', cleanup=True, moves=1)
	yield case('nested-owner-leaves', 'struct Child{owned int[] a;owned int[] b;int tag;}struct Parent{Child child;int extra;}int read(borrowed Parent p){return p.child.tag+p.extra;}int f(bool c){Parent p={child={a=new int[2],b=new int[3],tag=4},extra=3};{Parent q={child={a=new int[1],b=new int[2],tag=5},extra=2};if(c){return read(q)+read(p);}}return read(p);}int main(){return f(true)+f(false)-21;}', cleanup=True, loans=True)
	yield case('ordered-owned-arguments', PACKET+'int left(Packet p){return p.tag;}int right(Packet p){return p.tag;}int pair(int a,int b){return a*10+b;}int main(){Packet a={data=new int[2],tag=4};Packet b={data=new int[3],tag=2};return pair(left(move a),right(move b))-42;}', calls=3, moves=2, cleanup=True)
