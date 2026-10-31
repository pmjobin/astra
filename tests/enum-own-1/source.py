# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Authored owning/generic enum source contracts and actual native witnesses."""
import json
import os
from pathlib import Path
import subprocess
import sys

POSITIVE = {
	'copied-outcomes': '''
enum Error { Invalid, Version(int version) }
enum Result<T,E> { Success(T value), Error(E error) }
enum VoidResult<E> { Success, Error(E error) }
struct Header { int version; int count; }
int main() {
	var scalar = Result<int,Error>.Success(7);
	Header header = {version=3,count=4};
	var record = Result<Header,Error>.Success(header);
	match (scalar) { case Result<int,Error>.Success(n): { if (n != 7) { return 1; } } else: { return 2; } }
	match (record) { case Result<Header,Error>.Success(h): { if (h.version+h.count != 7) { return 3; } } else: { return 4; } }
	var empty = VoidResult<Error>.Success();
	match (empty) { case VoidResult<Error>.Success(): { return 0; } else: { return 5; } }
}
''',
	'generic-forwarding': '''
enum Fault { Invalid }
enum Outcome<T,E> { Value(T value), Error(E error), Empty }
Outcome<T,E> relay<T,E>(Outcome<T,E> input) { return input; }
int main() {
	var input = Outcome<int,Fault>.Value(17);
	var output = relay<int,Fault>(input);
	match (output) { case Outcome<int,Fault>.Value(n): { return n-17; } else: { return 1; } }
}
''',
	'ordinary-generic-value': '''
enum Error { Invalid, Number(int value) }
T identity<T>(T input) { return input; }
int main() {
	var input = Error.Number(19);
	var output = identity(input);
	var direct = identity(Error.Number(23));
	match (output) { case Error.Number(n): { if (n != 19) { return 1; } } else: { return 2; } }
	match (direct) { case Error.Number(n): { return n-23; } else: { return 3; } }
}
''',
	'owning-cleanup': '''
enum State { Empty, Ready(owned int[] data) }
int main() {
	owned int[] data = new int[3];
	data[0] = 11;
	var state = State.Ready(move data);
	match (state) { case State.Ready(view): { if (len(view) != 3 || view[0] != 11) { return 1; } } else: { return 2; } }
	return 0;
}
''',
	'owning-consuming-result': '''
enum State { Empty, Ready(owned int[] data) }
owned int[] take(State state) {
	match (move state) { case State.Ready(data): { return move data; } else: { return new int[0]; } }
}
int main() {
	var state = State.Ready(new int[5]);
	owned int[] data = take(move state);
	return len(data)-5;
}
''',
	'generic-owning-forward': '''
enum Error { Invalid }
enum ArrayResult<T,E> { Success(owned T[] value), Error(E error) }
ArrayResult<T,E> relay<T,E>(ArrayResult<T,E> input) { return move input; }
ArrayResult<T,Error> produce<T>(int count) { owned T[] data = new T[count]; return ArrayResult<T,Error>.Success(move data); }
int main() {
	var first = produce<int>(4);
	var second = relay<int,Error>(move first);
	match (move second) { case ArrayResult<int,Error>.Success(data): { return len(data)-4; } else: { return 1; } }
}
''',

	'nested-replacement-and-ignore': '''
enum State { Empty, Ready(owned int[] data, owned int[] second, int count) }
enum Outer { Empty, Child(State state, owned int[] tail) }
State rearm(State state) { return move state; }
int main() {
	var state = State.Ready(new int[1], new int[2], 3);
	state = rearm(move state);
	var outer = Outer.Child(move state, new int[4]);
	match (outer) { case Outer.Child(child, tail): { if (len(tail) != 4) { return 1; } match (child) { case State.Ready(a, b, n): { if (len(a)+len(b) != n) { return 2; } } else: { return 3; } } } else: { return 4; } }
	match (move outer) { case Outer.Child(child, _): { match (move child) { case State.Ready(second=b, count=n, data=_): { return len(b)-2; } else: { return 5; } } } else: { return 6; } }
}
''',
	'reserved-buffer-read': '''
enum State { Ready(owned int[] data, int length) }
int main() { owned int[] data = new int[7]; var state = State.Ready(move data, len(data)); match (move state) { case State.Ready(value, n): { return len(value)-n; } } }
''',
	'empty-is-owning': '''
enum State { Empty, Ready(owned int[] data) }
State relay(State value) { return move value; }
int main() { var state = State.Empty(); var next = relay(move state); next = State.Ready(new int[1]); next = State.Empty(); match (move next) { case State.Empty(): { return 0; } else: { return 1; } } }
''',

}

POSITIVE['nested-generic-premise'] = '\n'.join([
	'enum Inner<T>{Ready(owned T[] value),Empty}',
	'enum Outer<T>{Child(Inner<T> value),Empty}',
	'Outer<T> make<T>(int n){return Outer<T>.Child(Inner<T>.Ready(new T[n]));}',
	'Outer<T> relay<T>(Outer<T> input){return move input;}',
	'int main(){var a=make<int>(3);var b=relay<int>(move a);match(move b){case Outer<int>.Child(v):{match(move v){case Inner<int>.Ready(data):{return len(data)-3;}else:{return 1;}}}else:{return 2;}}}'
])
POSITIVE['inferred-known-owning-argument'] = 'enum O{Ready(owned int[] a),Empty} int take<T>(O a,T value){match(move a){else:{return 0;}}} int main(){var a=O.Empty();return take(move a,1);}'
POSITIVE['early-loop-cleanup'] = '''
enum State { Ready(owned int[] value), Failed(int reason), Empty }
int early(bool selected) {
	var state = State.Ready(new int[3]);
	match (state) { case State.Ready(view): { if (selected) { return len(view)-3; } } else: { return 1; } }
	return 0;
}
State rearm(State input) { input = State.Failed(7); input = State.Ready(new int[2]); return move input; }
int main() {
	if (early(true) != 0 || early(false) != 0) { return 1; }
	int n = 0;
	while (n < 5) {
		var state = State.Ready(new int[1]);
		match (state) { case State.Ready(view): { n = n + len(view); if (n < 3) { continue; } if (n == 4) { break; } } else: { return 2; } }
	}
	var ready = rearm(State.Ready(new int[4]));
	ready = State.Empty(); ready = State.Ready(new int[2]); ready = State.Failed(5);
	match (move ready) { case State.Failed(reason): { return n+reason-9; } else: { return 3; } }
}
'''

NEGATIVE = {
	'self-move': ('enum E{Empty,Data(owned int[] a)} void f(){var a=E.Empty();a=move a;}', 'move'),
	'dropped-owning-result': ('enum E{Empty,Data(owned int[] a)} E make(){return E.Empty();} void f(){make();}', 'owner'),
	'uninitialized-enum': ('enum E{Empty,Data(owned int[] a)} void f(){E a;}', 'initial'),
	'outer-token-identity': ('enum A<T>{Data(owned T[] a)} A<T> f<T,U>(A<U> a){return move a;}', 'exact'),
	'wrong-applied-pattern': ('enum E<T>{Empty} void f(){var e=E<int>.Empty();match(e){case E<bool>.Empty():{}}}', 'exact'),
	'unused-owning-field': ('enum E<T>{Data(owned T a)}', 'array'),
	'redundant-owned-enum': ('enum E{Data(owned int[] a)} void f(){owned E e=E.Data(new int[1]);}', 'owned'),
	'enum-containing-class': ('enum E{Empty} class C{E e;init(){}}', 'enum'),
	'inspection-record-mutate': ('struct R{int x;} enum E{Data(owned R[] a)} void f(){var a=E.Data(new R[1]);match(a){case E.Data(v):{v[0].x=1;}}}', 'read-only'),
	'phantom-identity': ('enum Token<T>{Empty} void f(){Token<int> a=Token<bool>.Empty();}', 'exact'),
	'missing-enum-arguments': ('enum Value<T>{Data(T data)} void f(){var a=Value.Data(1);}', 'explicit'),
	'enum-in-struct': ('enum E{Empty} struct Box<T>{T value;} void f(){Box<E> b={value=E.Empty()};}', 'enum-containing'),
	'enum-element': ('enum E{Empty} void f(){owned E[] a=new E[1];}', 'element'),
	'borrowed-payload': ('enum E{Data(borrowed int[] data)}', 'borrowed'),
	'copy-owning-empty': ('enum E{Empty,Data(owned int[] a)} void f(){var a=E.Empty();var b=a;}', 'move'),
	'moved-enum-use': ('enum E{Empty,Data(owned int[] a)} void f(){var a=E.Empty();var b=move a;match(a){else:{}}}', 'moved'),
	'double-enum-move': ('enum E{Empty,Data(owned int[] a)} void use(E a,E b){} void f(){var a=E.Empty();use(move a,move a);}', 'reserved'),
	'inspection-mutate': ('enum E{Data(owned int[] a)} void f(){var a=E.Data(new int[1]);match(a){case E.Data(v):{v[0]=1;}}}', 'read-only'),
	'inspection-forward': ('enum E{Data(owned int[] a)} void use(int[] a){} void f(){var a=E.Data(new int[1]);match(a){case E.Data(v):{use(v);}}}', 'inspection'),
	'inspection-root-move': ('enum E{Data(owned int[] a)} void use(E a){} void f(){var a=E.Data(new int[1]);match(a){case E.Data(v):{use(move a);}}}', 'inspection'),
	'owning-generic-value': ('enum E{Empty,Data(owned int[] a)} T id<T>(T value){return value;} void f(){var a=E.Empty();var b=id(move a);}', 'generic'),
	'unstated-element-premise': ('enum A<T>{Data(owned T[] a)} void f<T>(){var a=A<T>.Data(new T[1]);}', 'element'),
	'double-buffer-capture': ('enum E{Data(owned int[] a,owned int[] b)} void f(){owned int[] a=new int[1];var e=E.Data(move a,move a);}', 'reserved'),

}

def main(compiler, output):
	output.mkdir(parents=True, exist_ok=True)
	checks = []
	for name, code in POSITIVE.items():
		path = output / (name + '.astra'); path.write_text(code)
		binary = output / name
		command = [str(compiler), str(path), '-o', str(binary)]
		compiled = subprocess.run(command, capture_output=True, text=True, env={**os.environ, 'CCACHE_DISABLE': '1'})
		assert compiled.returncode == 0 and not compiled.stderr, (name, compiled.stderr)
		executed = subprocess.run([str(binary)], capture_output=True, text=True)
		assert executed.returncode == 0 and not executed.stdout and not executed.stderr, (name, executed)
		checks.append({'name': name, 'compiled': True, 'native_exit': executed.returncode})
	for name, (code, diagnostic) in NEGATIVE.items():
		path = output / (name + '.astra'); path.write_text(code)
		result = subprocess.run([str(compiler), '--check', str(path)], capture_output=True, text=True)
		assert result.returncode != 0 and diagnostic in result.stderr, (name, result.returncode, result.stderr)
		checks.append({'name': name, 'rejected': True, 'reason': diagnostic})
	(output / 'checks.json').write_text(json.dumps(checks, indent=2) + '\n')
	print(json.dumps({'native': len(POSITIVE), 'rejected': len(NEGATIVE)}))

if __name__ == '__main__':
	main(*(Path(argument).resolve() for argument in sys.argv[1:]))
