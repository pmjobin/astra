#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Predeclared real-source specialization witnesses and independent expectations."""
EXISTING = {
	'explicit-int': 'tests/gen-infer/fixtures/explicit-basic.astra',
	'inferred-int': 'tests/gen-infer/fixtures/gen-infer-basic.astra',
	'explicit-bool': 'tests/gen-infer/fixtures/explicit-bool.astra',
	'explicit-f32': 'tests/gen-infer/fixtures/explicit-f32.astra',
	'ordered-arguments': 'tests/gen-infer/fixtures/explicit-multi.astra',
}
CASES = {
	'record-identity': '''struct Box<T> { T value; }
Box<int> increment(Box<int> value) { Box<int> result = value; result.value = result.value + 3; return result; }
int main() { Box<int> a = { value = 17 }; var b = increment(a); if (a.value != 17 || b.value != 20) return 1; return 0; }''',
	'record-nested': '''struct Box<T> { T value; }
struct Pair<T> { Box<T> left; Box<T> right; }
Pair<f64> echo(Pair<f64> p) { return p; }
int main() { Pair<f64> a = { left = { value = 1.5d }, right = { value = 2.75d } }; var b = echo(a); if (b.left.value != 1.5d || b.right.value != 2.75d) return 1; return 0; }''',
	'record-nominal': '''struct Left<T> { T value; }
struct Right<T> { T value; }
T identity<T>(T value) { return value; }
int main() { Left<int> a = { value = 23 }; Right<int> b = { value = 31 }; var x = identity<Left<int>>(a); var y = identity<Right<int>>(b); if (x.value != 23 || y.value != 31) return 1; return 0; }''',
	'method-concrete': '''class Echo<T> { init() {} T echo(T value) { return value; } }
int main() { var e = new Echo<int>(); if (e.echo(19) != 19 || e.echo(41) != 41) return 1; return 0; }''',
	'method-outer': '''class Echo<T> { init() {} U echo<U>(U value) { return value; } }
int main() { var e = new Echo<int>(); if (e.echo<f64>(2.25d) != 2.25d || e.echo<int>(37) != 37) return 1; return 0; }''',
	'owner-buffer': '''owned T[] relay<T>(owned T[] value) { return move value; }
int main() { var a = new int[7]; var b = relay<int>(move a); if (len(b) != 7) return 1; return 0; }''',
	'owner-early': '''owned T[] choose<T>(owned T[] value, bool ready) { if (ready) return move value; owned T[] other = new T[2]; return move other; }
int main() { var a = new f32[5]; var b = choose<f32>(move a, true); var c = new int[3]; var d = choose<int>(move c, false); if (len(b) != 5 || len(d) != 2) return 1; return 0; }''',
}
MULTISOURCE = [
	'tests/gen-infer/fixtures/gen-infer-multisource/generic.astra',
	'tests/gen-infer/fixtures/gen-infer-multisource/inferred.astra',
	'tests/gen-infer/fixtures/gen-infer-multisource/explicit.astra',
	'tests/gen-infer/fixtures/gen-infer-multisource/main.astra',
]
NEGATIVES = {
	'arity': 'T id<T>(T x) { return x; } int main() { return id<int,bool>(1); }',
	'conflicting-argument': 'T id<T>(T x) { return x; } int main() { return id<int>(true); }',
	'constraint': 'T add<T>(T x,T y) where T : Numeric { return x + y; } int main() { var b = add<bool>(true,false); return 0; }',
	'nominal': 'struct A<T> { T x; } struct B<T> { T x; } int take(A<int> x) { return x.x; } int main() { B<int> b = { x = 1 }; return take(b); }',
	'argument-order': 'B second<A,B>(A a,B b) { return b; } int main() { return second<int,bool>(true,1); }',
	'move-after-use': 'owned T[] id<T>(owned T[] x) { return move x; } int main() { var a = new int[3]; var b = id<int>(move a); return len(a); }',
	'recursive-expansion': 'T recur<T>(T x) { return recur<T>(x); } int main() { return recur<int>(1); }',
}
