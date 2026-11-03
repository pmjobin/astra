# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independently authored source witnesses; no candidate builder algorithm."""


def additional():
	yield dict(name='scalar-control', source='int add(int a,int b){return a+b;}int work(int n){int i=0;int total=0;while(i<n){i=i+1;if(i==2){continue;}if(i>5){break;}if(i==4){if(n==7){return total+30;}}total=add(total,i);}return total;}int main(){return work(0)+work(1)+work(3)+work(7)-40;}', status=0, exit=255)
	yield dict(name='wrapping', source='u32 bump(u32 x){return x+1;}int signed(int x){return x+1;}int main(){u32 top=4294967295;if(bump(top)!=0){return 1;}int max=2147483647;if(signed(max)!=-2147483648){return 2;}return 0;}', status=0, exit=0)
	yield dict(name='short-loan', source='struct Packet{owned int[] data;int tag;}bool take(Packet p){return p.tag==7;}int main(){Packet a={data=new int[2],tag=7};if(false&&take(move a)){return 1;}Packet b={data=new int[3],tag=7};if(true||take(move b)){return 0;}return 2;}', status=0, exit=0)
	yield dict(name='wrong-return', source='int f(){return true;}', status=4)
	yield dict(name='bad-field', source='struct Pair{int x;}int main(){Pair p={x=1};return p.y;}', status=4)
	yield dict(name='unknown-call', source='int f(Fn<int,int> code,int x){return code(x);}', status=3)
