# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Frozen independent runtime expectations; never imported by the emitter."""
SELECTION = {
	'branch': ['ssa-diamond', 'ssa-nested-diamond', 'ssa-and-skip', 'ssa-or-skip'],
	'loop': ['ssa-counter', 'ssa-nested-continue', 'ssa-break-version', 'nested-loops'],
	'call': ['ssa-separate-functions', 'ssa-chain', 'ssa-overwrite-join', 'ordered-owned-arguments'],
	'ownership': ['ssa-argument-order', 'ssa-owning-return', 'ssa-borrow-end', 'owner-loop-exits'],
	'extra': ['ssa-field-memory', 'scalar-control'],
}
NUMERIC = {
	'numeric-wrapping': 'u32 bump(u32 x){return x+1;}int next(int x){return x+1;}int main(){u32 x=4294967295;if(bump(x)!=0){return 1;}if(next(2147483647)!=-2147483648){return 2;}return 0;}',
	'numeric-signed-compare': 'int f(int a,int b){if(a<b){return 3;}if(a>=b){return 7;}return 9;}bool u(u32 a,u32 b){return a>b;}int main(){if(!u(4294967295,1)){return 1;}return f(-7,2)+f(5,-1)-10;}',
	'numeric-bitwise': 'u32 f(u32 x,u32 y){return (x&y)^(x|y);}int main(){if(f(12,10)!=6){return 1;}int x=-7;if((~x)!=6){return 2;}return 0;}',
	'numeric-division': 'int q(int a,int b){return a/b;}int r(int a,int b){return a%b;}int main(){if(q(-17,5)!=-3||r(-17,5)!=-2){return 1;}if(q(-2147483648,-1)!=-2147483648||r(-2147483648,-1)!=0){return 2;}return 0;}',
	'numeric-shifts': 'int s(int x,int n){return x>>n;}u32 u(u32 x,int n){return x>>n;}int l(int x,int n){return x<<n;}int main(){if(s(-16,2)!=-4||u(4294967295,4)!=268435455){return 1;}if(l(3,5)!=96){return 2;}return 0;}',
	'numeric-conversions': 'i64 widen(i8 x){return x as i64;}u64 wide(u8 x){return x as u64;}int main(){i8 a=-7;u8 b=250;if(widen(a)!=-7||wide(b)!=250){return 1;}i64 c=19;return (c as int)-19;}',
}
# Allocation/free order (requested element counts), independently hand-derived.
TRACES = {
	'ordered-owned-arguments': [('A',2),('A',3),('F',2),('F',3)],
	'ssa-argument-order': [('A',2),('A',3),('F',2),('F',3)],
	'ssa-owning-return': [('A',2),('A',2),('F',2),('F',2)]*2,
	'ssa-borrow-end': [('A',3),('F',3)],
	'owner-loop-exits': [('A',2),('A',3),('F',3),('F',2)]*5,
}
