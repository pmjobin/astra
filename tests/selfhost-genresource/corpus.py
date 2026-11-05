#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""New generic programs with independent, predeclared source-level oracles."""
import argparse
import json
from state import ROOT, RUNTIME, sha

CELL = '''struct Cell { int value; }
'''
ITEM = '''class Item {
	owned int[] bytes;
	int value;
	init(int value) { this.bytes = new int[3]; this.value = value; }
	int get() { return this.value * 2 + 1; }
}
'''
STORE = '''class Store<T> {
	owned T[] data;
	init() { this.data = new T[2]; }
	void grow() { var grown = new T[5]; grown[0] = this.data[0]; swap(this.data, grown); }
}
'''


def cases():
	vector = (ROOT/'lib/astra/collections/vector.astra').read_text()
	return {
		'cross-file-reuse': ([CELL+'T identity<T>(T value) { return value; }\n', 'Cell left(Cell value) { return identity<Cell>(value); }\n', 'Cell right(Cell value) { return identity<Cell>(value); }\n', 'int main() { Cell a = {value = 7}; var b = left(a); var c = right(b); if (a.value != 7 || c.value != 7) return 99; return 41; }\n'], 41),
		'lexical-and-nominal': ([CELL+'''struct Other { int value; }
T first<T>(T value) { return value; }
U second<U>(U value) { return value; }
int main() { Cell a = {value = 9}; Other b = {value = 13}; var x = first<Cell>(a); var y = second<Other>(b); var z = second<Cell>(x); if (z.value + y.value != 22) return 99; return 42; }
'''], 42),
		'nested-record-reuse': (['''struct Wrap<T> { T value; }
struct Pair<T> { Wrap<T> left; Wrap<T> right; }
T echo<T>(T value) { return value; }
int main() { Pair<f64> a = {left = {value = 1.25d}, right = {value = 3.5d}}; var b = echo<Pair<f64>>(a); var c = echo<Pair<f64>>(b); if (c.left.value != 1.25d || c.right.value != 3.5d) return 99; return 43; }
'''], 43),
		'owned-array-repeat': ([CELL+'''owned T[] relay<T>(owned T[] value) { return move value; }
int main() { Cell stamp = {value = 44}; var a = new bool[3]; a[2] = true; var b = relay<bool>(move a); var c = relay<bool>(move b); if (len(c) != 3 || !c[2]) return 99; return stamp.value; }
'''], 44),
		'cross-file-record-store': ([CELL+STORE, 'void grow_one(borrowed Store<Cell> value) { value.grow(); }\n', '''int main() { var a = new Store<Cell>(); var b = new Store<Cell>(); Cell x = {value = 17}; Cell y = {value = 23}; a.data[0] = x; b.data[0] = y; grow_one(a); grow_one(b); if (len(a.data) != 5 || a.data[0].value != 17 || b.data[0].value != 23) return 99; return 45; }
'''], 45),
		'owned-class-repeat': ([CELL+ITEM+vector, '''int main() { Cell stamp = {value = 46}; var a = new Vector<Item>(1); var b = new Vector<Item>(1); var x = new Item(3); var y = new Item(7); bool ax = a.append(move x); bool by = b.append(move y); var ar = a.take(0); var br = b.take(0); if (ar.get() != 7 || br.get() != 15 || a.count() + b.count() != 0) return 99; return stamp.value; }
'''], 46),
		'nested-owned-retirement': ([CELL+ITEM.replace('\towned int[] bytes;\n', '').replace('this.bytes = new int[3]; ', '')+'''class Envelope {
	owned Item child;
	init(owned Item item) { this.child = move item; }
}
'''+vector, '''int main() { Cell stamp = {value = 47}; var a = new Vector<Envelope>(1); var first = new Item(8); var x = new Envelope(move first); bool ok = a.append(move x); var second = new Item(11); var y = new Envelope(move second); a.replace(0, move y); var result = a.take(0); if (result.child.value != 11 || a.count() != 0) return 99; return stamp.value; }
'''], 47),
		'equal-layout-distinct-stores': ([CELL+'struct Other { int value; }\n'+STORE, '''int main() { var a = new Store<Cell>(); var b = new Store<Other>(); Cell x = {value = 29}; Other y = {value = 31}; a.data[0] = x; b.data[0] = y; a.grow(); b.grow(); if (a.data[0].value != 29 || b.data[0].value != 31 || len(b.data) != 5) return 99; return 48; }
'''], 48),
		'finite-generic-dependency': ([CELL+'''T identity<T>(T value) { return value; }
U forward<U>(U value) { return identity<U>(value); }
int main() { Cell a = {value = 37}; var b = forward<Cell>(a); var c = identity<Cell>(b); if (c.value != 37 || a.value != 37) return 99; return 49; }
'''], 49),
		'bounded-generic-loop': ([CELL+'''T repeat<T>(T value, int count) { int i = 0; while (i < count) { i = i + 1; } return value; }
int main() { Cell a = {value = 41}; var b = repeat<Cell>(a, 7); if (b.value != 41) return 99; return 50; }
'''], 50),
		'cross-file-owner-transfer': ([CELL+'''owned T[] choose_buffers<T>(owned T[] first, owned T[] second) { swap(first, second); return move first; }
''', '''owned int[] provide() { var a = new int[2]; var b = new int[4]; b[3] = 53; return choose_buffers<int>(move a, move b); }
''', '''int main() { Cell stamp = {value = 51}; var a = provide(); var b = new int[1]; b[0] = 59; var result = choose_buffers<int>(move a, move b); if (len(result) != 1 || result[0] != 59) return 99; return stamp.value; }
'''], 51),
		'generic-rearm-loop': ([CELL+'''owned T[] relay<T>(owned T[] value) { return move value; }
int main() { Cell stamp = {value = 52}; int i = 0; int sum = 0; while (i < 5) { var a = new int[2]; a[1] = i + 1; var b = relay<int>(move a); sum = sum + b[1]; i = i + 1; } if (sum != 15) return 99; return stamp.value; }
'''], 52),
	}


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', default='v2'); a = p.parse_args()
	assert a.version.replace('-', '').isalnum()
	leaf = RUNTIME/('corpus-'+a.version); leaf.mkdir(exist_ok=False)
	selection = []
	for name, (texts, expected) in cases().items():
		sources = []
		for ordinal, text in enumerate(texts):
			path = leaf/(name+'-'+str(ordinal)+'.astra'); path.write_text(text)
			sources.append(dict(path=str(path), bytes=path.stat().st_size, sha256=sha(path)))
		selection.append(dict(name=name, sources=sources, expected_exit=expected, oracle='Predeclared explicit field/element/length assertions and manual return value; C0 is compiled and executed independently by the native qualifier'))
	assert len(selection) == len({tuple(s['sha256'] for s in row['sources']) for row in selection}) == 12
	(leaf/'selection.json').write_text(json.dumps(selection, indent=2)+'\n')
	print('Frozen 12 new source identities; qualification still required')


if __name__ == '__main__':
	main()
