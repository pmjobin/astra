#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent executable source witnesses for reference substitution and owners."""
import argparse
import json
from state import RUNTIME, sha

ASSERT = 'void require(bool ok) { if (!ok) { var empty = new int[0]; int bad = empty[1]; } }\n'
RECORD = 'struct Parcel<T> { T item; }\n'
IDENTITY = 'T preserve<T>(T value) { T local = value; return local; }\n'
STORE = '''struct Sample { int amount; }
struct Twin { int amount; }
class Cabinet<T> {
	owned T[] rows;
	int stamp;
	init() { this.rows = new T[2]; this.stamp = 0; }
	T retain(T value) { T local = value; this.stamp = this.stamp + 1; return local; }
	U forward<U>(U value) { U saved = value; this.stamp = this.stamp + 2; return saved; }
	int count() { return this.stamp; }
}
'''


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', default='v2'); a = p.parse_args()
	leaf = RUNTIME/('corpus-'+a.version); leaf.mkdir(exist_ok=False); cases = {}
	cases['exact-local-reuse'] = (RECORD+IDENTITY+'''int main() { Parcel<int> a = {item = 17}; var b = preserve<Parcel<int>>(a); var c = preserve<Parcel<int>>(b); require(a.item == 17 && c.item == 17); return 73; }
''', 73, 'Repeated exact function/record specialization and local symbol substitution')
	cases['nominal-same-layout'] = (STORE+IDENTITY+'''int main() { Sample a = {amount = 21}; Twin b = {amount = 34}; var left = new Cabinet<Sample>(); var right = new Cabinet<Twin>(); var x = left.retain(preserve<Sample>(a)); var y = right.retain(preserve<Twin>(b)); require(x.amount == 21 && y.amount == 34 && left.count() == 1 && right.count() == 1); return 74; }
''', 74, 'Different nominal arguments and exact enclosing Class instances with equal layout')
	cases['outer-field-local'] = (STORE+'''int main() { var cabinet = new Cabinet<Sample>(); Sample input = {amount = 9}; var result = cabinet.retain(input); require(result.amount == 9 && cabinet.count() == 1); return 75; }
''', 75, 'Concrete method of generic Class uses body local and enclosing Class field')
	cases['generic-method-outer'] = (STORE+'''int main() { var cabinet = new Cabinet<Sample>(); Twin value = {amount = 28}; var result = cabinet.forward<Twin>(value); require(result.amount == 28 && cabinet.count() == 2); return 76; }
''', 76, 'Generic method substitutes its own local and preserves specialized outer Class')
	cases['nested-direct-record'] = (STORE+'''class Frame { owned Cabinet<Sample> child; init(owned Cabinet<Sample> child) { this.child = move child; } }
int main() { var child = new Cabinet<Sample>(); var frame = new Frame(move child); Sample input = {amount = 13}; var result = frame.child.retain(frame.child.forward<Sample>(input)); require(result.amount == 13 && frame.child.count() == 3); return 77; }
''', 77, 'Nested result and record argument on projected once-evaluated receiver')
	cases['borrowed-exact-alias'] = (STORE+'''Sample invoke(borrowed Cabinet<Sample> left, borrowed Cabinet<Sample> right, Sample value) { var saved = left.forward<Sample>(value); return right.retain(saved); }
int main() { var cabinet = new Cabinet<Sample>(); Sample input = {amount = 33}; var result = invoke(cabinet, cabinet, input); require(result.amount == 33 && cabinet.count() == 3); return 78; }
''', 78, 'Two borrowed aliases preserve one owner and the private pointer receiver ABI')
	cases['shadowed-member'] = (RECORD+'''class Shadow<X> { int selected; owned X[] trace; init() { this.selected = 7; this.trace = new X[2]; } T choose<T>(T selected) { T local = selected; this.selected = this.selected + 1; return local; } }
int main() { var shadow = new Shadow<int>(); Parcel<int> input = {item = 42}; var first = shadow.choose<Parcel<int>>(input); var second = shadow.choose<Parcel<int>>(input); require(first.item == 42 && second.item == 42 && shadow.selected == 9); return 79; }
''', 79, 'A generic method parameter shadows a Class field, retaining exact local and qualified member identities')
	cases['branch-owner-cleanup'] = (STORE+'''int compute(bool early) { var cabinet = new Cabinet<Sample>(); Sample input = {amount = 15}; var result = cabinet.forward<Sample>(input); if (early) return result.amount + cabinet.count(); var again = cabinet.retain(result); return again.amount + cabinet.count(); }
int main() { require(compute(true) == 17 && compute(false) == 18); return 80; }
''', 80, 'Early-return and later-return owner cleanup after specialized method calls')
	cases['record-copy-owner'] = (STORE+'''int main() { var cabinet = new Cabinet<Sample>(); Sample original = {amount = 18}; var copied = cabinet.forward<Sample>(original); copied.amount = 29; require(original.amount == 18 && copied.amount == 29 && cabinet.count() == 2); return 81; }
''', 81, 'Copied value record remains distinct from its owning Class receiver')
	cases['array-owned-result'] = (STORE+IDENTITY+'''int main() { var cabinet = new Cabinet<Sample>(); var rows = new Sample[2]; Sample input = {amount = 47}; var value = cabinet.retain(preserve<Sample>(input)); rows[1] = value; var copied = cabinet.forward<Sample>(rows[1]); require(copied.amount == 47 && cabinet.count() == 3); return 82; }
''', 82, 'References in owner-bearing record buffers and nested specialized calls')
	cases['unrelated-family'] = ('''struct Pulse { i64 ticks; bool active; }
class Oscillator<X> { owned X[] samples; i64 total; init() { this.samples = new X[3]; this.total = 4; } X carry(X input) { X remembered = input; this.total = this.total + 5; return remembered; } i64 read() { return this.total; } }
int main() { var clock = new Oscillator<Pulse>(); Pulse input = {ticks = 4000000001, active = true}; var result = clock.carry(input); i64 expected = 4000000001; i64 nine = 9; require(result.ticks == expected && result.active && clock.read() == nine); return 83; }
''', 83, 'Independent Class, record and i64 family with different member names')
	cases['owner-parameter-transfer'] = (STORE+'''int consume(owned Cabinet<Sample> cabinet) { Sample value = {amount = 51}; var result = cabinet.forward<Sample>(value); return result.amount + cabinet.count(); }
int main() { var cabinet = new Cabinet<Sample>(); require(consume(move cabinet) == 53); return 84; }
''', 84, 'Explicit owner transfer followed by borrowed generic method and normal cleanup')
	cases['recursive-member-binding'] = ('''class Countdown { owned int[] trace; int visits; init() { this.trace = new int[4]; this.visits = 0; } int walk(int remaining) { this.visits = this.visits + 1; if (remaining == 0) return 3; return this.walk(remaining - 1) + 2; } }
int main() { var counter = new Countdown(); require(counter.walk(3) == 9 && counter.visits == 4); return 86; }
''', 86, 'Direct reproduction of lexical recursive member versus concrete function reference')
	cases['generic-recursive-member'] = ('''struct Item { int value; }
class Repeater<T> { owned T[] data; int calls; init() { this.data = new T[2]; this.calls = 0; } U repeat<U>(U value, int remaining) { this.calls = this.calls + 1; if (remaining == 0) return value; return this.repeat<U>(value, remaining - 1); } }
int main() { var repeater = new Repeater<Item>(); Item input = {value = 57}; var result = repeater.repeat<Item>(input, 2); require(result.value == 57 && repeater.calls == 3); return 87; }
''', 87, 'Recursive genuinely generic method retains source identity in a generic Class')
	selection = []
	for name, (source, expected, oracle) in cases.items():
		path = leaf/(name+'.astra'); path.write_text(ASSERT+source)
		selection.append(dict(name=name, sources=[dict(path=str(path), bytes=path.stat().st_size, sha256=sha(path))], expected_exit=expected, oracle=oracle))
	provider = leaf/'provider.astra'; provider.write_text('namespace Relay; struct Packet { int code; } T copy<T>(T input) { T kept = input; return kept; }\n')
	entry = leaf/'qualified-main.astra'; entry.write_text(ASSERT+'int main() { Relay.Packet input = {code = 32}; var result = Relay.copy<Relay.Packet>(input); require(result.code == 32); return 85; }\n')
	selection.append(dict(name='qualified-unrelated-module', sources=[dict(path=str(p), bytes=p.stat().st_size, sha256=sha(p)) for p in (provider, entry)], expected_exit=85, oracle='Namespace-qualified generic global and exact nominal record from another module'))
	(leaf/'selection.json').write_text(json.dumps(selection, indent=2)+'\n')
	print(len(selection), 'new source identities; qualification remains separate')


if __name__ == '__main__':
	main()
