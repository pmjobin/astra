#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Distinct source contracts for the finite generic Class profile."""
ITEM = '''class Item {
	int value;
	init(int value) { this.value = value; }
	int get() { return this.value; }
}
'''
RECORD = 'struct Item { bool flag; f64 weight; int value; }\n'
CASES = [
	('class-empty', ITEM, 'int main() { var v = new Vector<Item>(0); return v.count() + v.capacity(); }', 0),
	('class-initial-reserve', ITEM, 'int main() { var v = new Vector<Item>(7); return v.capacity() + v.count(); }', 7),
	('class-grow-shift', ITEM, '''int main() {
	var v = new Vector<Item>(1); int i = 0;
	while (i < 5) { var item = new Item(i + 1); bool ok = v.append(move item); i = i + 1; }
	var middle = v.take(1); var tail = v.take(3);
	return middle.get() * 10 + tail.get() + v.count();
}''', 28),
	('class-replace', ITEM, '''int main() {
	var v = new Vector<Item>(2); var a = new Item(4); bool ok = v.append(move a);
	var b = new Item(9); v.replace(0, move b); var result = v.take(0);
	return result.get() + v.count();
}''', 9),
	('class-reserve-refusal', ITEM, '''int main() {
	var v = new Vector<Item>(2); var a = new Item(6); bool ok = v.append(move a);
	if (v.reserve(-1)) return 90;
	if (v.capacity() != 2 || v.count() != 1) return 91;
	var result = v.take(0); return result.get();
}''', 6),
	('class-owner-relay', ITEM + '''owned Vector<Item> make(int seed) {
	var v = new Vector<Item>(1); var a = new Item(seed); bool ok = v.append(move a); return move v;
}
int consume(owned Vector<Item> v) { var result = v.take(0); return result.get(); }
''', 'int main() { var v = make(13); return consume(move v); }', 13),
	('class-early-cleanup', ITEM + '''int use(bool early) {
	var v = new Vector<Item>(1); var a = new Item(6); bool ok = v.append(move a);
	if (early) return v.count();
	var result = v.take(0); return result.get();
}
''', 'int main() { return use(true) + use(false); }', 7),
	('class-loop-cleanup', ITEM, '''int main() {
	int i = 0; int sum = 0;
	while (i < 3) { var v = new Vector<Item>(1); var a = new Item(i + 1); bool ok = v.append(move a); sum = sum + v.count(); i = i + 1; }
	return sum;
}''', 3),
	('class-nested-owner', ITEM + '''class Envelope {
	owned Item child;
	init(int value) { var item = new Item(value); this.child = move item; }
	int get() { return this.child.get(); }
}
''', '''int main() {
	var v = new Vector<Envelope>(1); var a = new Envelope(17); bool ok = v.append(move a);
	var b = new Envelope(18); v.replace(0, move b); var result = v.take(0); return result.get();
}''', 18),
	('record-layout', RECORD, '''int main() {
	var v = new Vector<Item>(2); Item item = {flag = true, weight = 2.5, value = 11};
	bool ok = v.append(item); var result = v.take(0);
	if (!result.flag || result.weight != 2.5) return 90;
	return result.value + item.value;
}''', 22),
	('record-grow-replace', RECORD, '''int main() {
	var v = new Vector<Item>(0); Item a = {flag = true, weight = 1.5, value = 2};
	int i = 0; while (i < 4) { bool ok = v.append(a); i = i + 1; }
	Item b = {flag = false, weight = 7.5, value = 19}; v.replace(1, b);
	var first = v.take(0); var result = v.take(0);
	if (result.flag || result.weight != 7.5) return 90;
	return first.value + result.value + v.count();
}''', 23),
	('record-nominal-separation', RECORD + 'struct Other { bool flag; f64 weight; int value; }\n', '''int main() {
	var a = new Vector<Item>(1); var b = new Vector<Other>(3);
	Item x = {flag = true, weight = 1.0, value = 7}; Other y = {flag = false, weight = 2.0, value = 8};
	bool ax = a.append(x); bool by = b.append(y); var ar = a.take(0); var br = b.take(0);
	return ar.value + br.value + a.capacity() + b.capacity();
}''', 19),
]

# Separate nominal declaration, deliberately generated from the unchanged library
# bytes at freeze time; the compiler implementation never sees this transformation.
ALTERNATE = ('alternate-class', ITEM, '''int main() {
	var v = new Sequence<Item>(1); var a = new Item(21); bool ok = v.append(move a);
	var result = v.take(0); return result.get();
}''', 21)

CROSS = ('cross-file', ITEM + '''owned Vector<Item> provide(int value) {
	var v = new Vector<Item>(2); var item = new Item(value); bool ok = v.append(move item); return move v;
}
''', 'int main() { var v = provide(23); var result = v.take(0); return result.get(); }', 23)

SUPPLEMENTAL = [
	('nested-slot-owner', '''class Cell {
	owned int[] data;
	int value;
	init(int value) { this.data = new int[2]; this.value = value; }
	int get() { return this.value; }
}
''', '''int main() {
	var v = new Vector<Cell>(2); var a = new Cell(31); bool ok = v.append(move a);
	var b = new Cell(32); v.replace(0, move b); var result = v.take(0); return result.get();
}''', 32),
	('constructor-failure', ITEM, 'int main() { var v = new Vector<Item>(4); return v.count(); }', 0),
	('combined-mutations', ITEM + '''struct Row { bool flag; f64 weight; int value; }
struct Other { bool flag; f64 weight; int value; }
''', '''int main() {
	var a = new Vector<Row>(4); var b = new Vector<Other>(2); var c = new Vector<Item>(3);
	Row x = {flag = true, weight = 2.5, value = 5}; Other y = {flag = false, weight = 3.5, value = 6};
	bool ax = a.append(x); bool ax2 = a.append(x); bool by = b.append(y);
	a.replace(0, x); var ar = a.take(0); var br = b.take(0);
	var item = new Item(7); bool ci = c.append(move item); var cr = c.take(0);
	return ar.value + br.value + cr.get();
}''', 18),
]
