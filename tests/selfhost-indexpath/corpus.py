# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent input programs and arithmetic expectations, frozen before edits."""
ROW = 'struct Row { bool tag; f64 weight; int code; }\n'
STORE = ROW+'''class Store {
	owned Row[] items;
	init(int n) { this.items = new Row[n]; }
	int read(int i) { return this.items[i].code; }
}
'''
CASES = [
	('store-first-last', STORE, '''int main() {
	var s = new Store(3); Row a = {tag = true, weight = 2.5, code = 7}; Row b = {tag = false, weight = 9.5, code = 13};
	s.items[0] = a; s.items[2] = b; return s.items[0].code + s.items[2].code;
}''', 20),
	('store-loop', STORE, '''int main() {
	var s = new Store(4); int i = 0;
	while (i < 4) { Row r = {tag = true, weight = 1.5, code = i + 1}; s.items[i] = r; i = i + 1; }
	i = 0; int sum = 0; while (i < 4) { sum = sum + s.read(i); i = i + 1; } return sum;
}''', 10),
	('nested-record', '''struct Child { int first; int last; }
struct Parent { bool tag; Child child; f64 tail; }
class Ledger { owned Parent[] rows; init(int n) { this.rows = new Parent[n]; } }
''', '''int main() { var s = new Ledger(2); Parent r = {tag = true, child = {first = 3, last = 17}, tail = 2.5}; s.rows[1] = r; return s.rows[1].child.last + s.rows[1].child.first; }''', 20),
	('generic-array-a', ROW+'''class Shelf<T> {
	owned T[] values;
	init(int n) { this.values = new T[n]; }
}
''', '''int main() { var s = new Shelf<Row>(2); Row r = {tag = true, weight = 3.5, code = 23}; s.values[1] = r; return s.values[1].code; }''', 23),
	('generic-array-b', '''struct Reading { int code; f64 wide; bool valid; }
class Shelf<T> { owned T[] values; init(int n) { this.values = new T[n]; } }
''', '''int main() { var s = new Shelf<Reading>(1); Reading r = {code = 29, wide = 4.5, valid = true}; s.values[0] = r; if (!s.values[0].valid || s.values[0].wide != 4.5) return 90; return s.values[0].code; }''', 29),
	('detached-snapshot', STORE, '''int main() { var s = new Store(1); Row r = {tag = true, weight = 1.5, code = 31}; s.items[0] = r; var copy = s.items[0]; copy.code = 2; return s.items[0].code + copy.code; }''', 33),
	('owner-transfer', STORE+'''owned Store relay(owned Store s) { return move s; }
''', '''int main() { var a = new Store(1); Row r = {tag = true, weight = 1.5, code = 37}; a.items[0] = r; var s = relay(move a); return s.items[0].code; }''', 37),
	('early-return', STORE+'''int read(bool early) { var s = new Store(2); Row r = {tag = true, weight = 1.5, code = 19}; s.items[1] = r; if (early) return s.items[1].code; return s.items[0].code; }
''', 'int main() { return read(true) + read(false); }', 19),
	('empty-short-circuit', STORE, '''int main() { var s = new Store(0); if (len(s.items) != 0 && s.items[0].code == 99) return 90; return len(s.items); }''', 0),
	('local-array', ROW, '''int main() { var rows = new Row[3]; Row r = {tag = true, weight = 1.5, code = 41}; rows[2] = r; return rows[2].code; }''', 41),
	('equal-layout-nominal', ROW+'''struct Other { bool tag; f64 weight; int code; }
class Pair { owned Row[] a; owned Other[] b; init() { this.a = new Row[1]; this.b = new Other[1]; } }
''', '''int main() { var s = new Pair(); Row a = {tag = true, weight = 1.5, code = 5}; Other b = {tag = false, weight = 2.5, code = 43}; s.a[0] = a; s.b[0] = b; return s.a[0].code + s.b[0].code; }''', 48),
]
NEGATIVES = {
	'wrong-nominal': ROW+'struct Other { bool tag; f64 weight; int code; } int main() { var a = new Row[1]; Other r = {tag = true, weight = 1.5, code = 1}; a[0] = r; return 0; }',
	'wrong-index-type': STORE+'int main() { var s = new Store(1); return s.items[true].code; }',
	'unknown-field': STORE+'int main() { var s = new Store(1); return s.items[0].missing; }',
	'moved-owner': STORE+'int main() { var a = new Store(1); var b = move a; return a.items[0].code; }',
	'detached-write': STORE+'int main() { var a = new Store(1); a.items[0].code = 7; return 0; }',
}
