# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""C0 premises; each retained freeze records its actual implementation phase."""
PLAIN = '''class Item { int value; init(int value) { this.value = value; } }
'''
CASES = {
	'field-layout': ['class Item { bool tag; f64 wide; int value; init(int value) { this.tag = true; this.wide = 2.5d; this.value = value; } } int main() { var a = new Item(17); if (!a.tag || a.wide != 2.5d || a.value != 17) return 1; return 0; }'],
	'field-mutation': [PLAIN+'int main() { var a = new Item(17); a.value = 29; if (a.value != 29) return 1; return 0; }'],
	'direct-method': ['class Item { int value; init(int value) { this.value = value; } int add(int delta) { this.value = this.value + delta; return this.value; } } int main() { var a = new Item(17); if (a.add(5) != 22 || a.value != 22) return 1; return 0; }'],
	'owner-relay': [PLAIN+'owned T relay<T>(owned T value) where T : Ownable { return move value; } int main() { var a = new Item(17); var b = relay<Item>(move a); if (b.value != 17) return 1; return 0; }'],
	'owner-early': [PLAIN+'int read(bool early) { var a = new Item(17); if (early) return a.value; var b = new Item(29); return b.value; } int main() { if (read(true) != 17 || read(false) != 29) return 1; return 0; }'],
	'owner-loop': [PLAIN+'int main() { int i = 0; int sum = 0; while (i < 4) { var a = new Item(i + 1); sum = sum + a.value; i = i + 1; } if (sum != 10) return 1; return 0; }'],
	'owned-buffer': ['class Item { owned int[] values; init(int count) { this.values = new int[count]; } } int main() { var a = new Item(7); a.values[2] = 41; if (len(a.values) != 7 || a.values[2] != 41) return 1; return 0; }'],
	'nested-owner': [PLAIN+'class Parent { owned Item child; init(owned Item child) { this.child = move child; } } int main() { var a = new Item(17); var b = new Parent(move a); if (b.child.value != 17) return 1; return 0; }'],
	'bag-transfer': [PLAIN+'int main() { var bag = new Bag<Item>(); if (!bag.reserve(2)) return 2; var a = new Item(17); bag.append(move a); var b = bag.take(0); if (b.value != 17 || bag.count() != 0) return 1; return 0; }', '@bag'],
	'bag-replace': [PLAIN+'int main() { var bag = new Bag<Item>(); if (!bag.reserve(2)) return 2; var a = new Item(17); bag.append(move a); var b = new Item(29); bag.replace(0, move b); var c = bag.take(0); if (c.value != 29) return 1; return 0; }', '@bag'],
	'bag-nominal': [PLAIN+'class Other { f64 value; init(f64 value) { this.value = value; } } int main() { var a = new Bag<Item>(); var b = new Bag<Other>(); if (!a.reserve(1) || !b.reserve(1)) return 2; var x = new Item(17); var y = new Other(2.5d); a.append(move x); b.append(move y); var xx = a.take(0); var yy = b.take(0); if (xx.value != 17 || yy.value != 2.5d) return 1; return 0; }', '@bag'],
	'cross-source': [PLAIN, 'owned Item make(int value) { var item = new Item(value); return move item; }', 'int main() { var a = make(37); if (a.value != 37) return 1; return 0; }'],
	'cross-borrow-mutation': ['class Item { int value; init(int value) { this.value = value; } void set(int value) { this.value = value; } int read() { return this.value; } }', 'void update(Item item, int value) { item.set(value); }', 'int main() { var a = new Item(17); update(a, 37); if (a.read() != 37 || a.value != 37) return 1; return 0; }'],
	'cross-owner-branch': [PLAIN, 'owned Item choose(owned Item value, bool early) { if (early) return move value; var other = new Item(29); return move other; }', 'int main() { var a = new Item(17); var b = choose(move a, true); if (b.value != 17) return 1; var c = new Item(31); var d = choose(move c, false); if (d.value != 29) return 1; return 0; }'],
	'bag-growth-order': [PLAIN+'int main() { var bag = new Bag<Item>(); if (!bag.reserve(1)) return 2; var a = new Item(17); bag.append(move a); if (!bag.reserve(4)) return 2; var b = new Item(29); var c = new Item(31); bag.append(move b); bag.append(move c); var middle = bag.take(1); var first = bag.take(0); var last = bag.take(0); if (middle.value != 29 || first.value != 17 || last.value != 31 || bag.count() != 0 || bag.capacity() != 4) return 1; return 0; }', '@bag'],
	'nullable-owner-transport': [PLAIN+'owned Item none() { return null; } owned Item relay(owned Item value) { return move value; } int main() { owned Item empty = none(); owned Item a = relay(move empty); if (a != null) return 1; return 0; }'],
	'bag-reserve-refusal': [PLAIN+'int main() { var bag = new Bag<Item>(); if (bag.reserve(-1) || bag.count() != 0 || bag.capacity() != 0 || !bag.reserve(0)) return 1; if (!bag.reserve(1)) return 2; var a = new Item(17); bag.append(move a); if (bag.reserve(-9) || bag.count() != 1 || bag.capacity() != 1) return 1; var b = bag.take(0); if (b.value != 17) return 1; return 0; }', '@bag'],
}
C0_REFUSED = {
	'nullable-rearm': PLAIN+'int main() { Item a = null; if (a != null) return 1; var b = new Item(17); a = move b; if (a == null || a.value != 17) return 1; a = null; if (a != null) return 1; return 0; }',
	'owning-record-Class-field-access': PLAIN+'struct Holder { owned Item value; } int main() { var item = new Item(17); Holder holder = { value = move item }; if (holder.value.value != 17) return 1; return 0; }',
	'explicit-owned-record-parameter': PLAIN+'struct Holder { owned Item value; } void consume(owned Holder value) {} int main() { var item = new Item(17); Holder holder = { value = move item }; consume(move holder); return 0; }',
}
UNCHANGED_HEAP_CASES = [
	('unchanged-promised-owner', ['tests/structural-generics-15/nonnull-result-origins.astra'], 0),
	('unchanged-bag-take', ['tests/owned-state-6/prototypes/bag-take.astra', 'lib/astra/collections/bag.astra'], 0),
]
# Additional observers frozen after implementation; these do not replace the
# original preimplementation population or contribute to its distinct count.
RUNTIME_PROBES = {
	'observable-identity': [PLAIN+'bool same(Item a, Item b) { return a == b; } int main() { var a = new Item(17); var b = new Item(17); if (!same(a, a) || same(a, b)) return 1; return 0; }'],
	'reserve-allocation-failure': [PLAIN+'int main() { var bag = new Bag<Item>(); if (!bag.reserve(1)) return 2; var a = new Item(17); bag.append(move a); bool grown = bag.reserve(4); if (bag.count() != 1) return 1; if (grown) { if (bag.capacity() != 4) return 1; } else { if (bag.capacity() != 1) return 1; } var b = bag.take(0); if (b.value != 17 || bag.count() != 0) return 1; return 0; }', '@bag'],
	'nullable-child-result': [PLAIN+'owned Item none() { return null; } class Parent { owned Item child; init() { this.child = none(); } } int main() { var p = new Parent(); return 0; }'],
	'nullable-child-move': [PLAIN+'owned Item none() { return null; } class Parent { owned Item child; init(owned Item child) { this.child = move child; } } int main() { owned Item empty = none(); var p = new Parent(move empty); return 0; }'],
}
# Exact, unchanged Class declaration including all fields and constructor is
# extracted from flow-model.astra at freeze time; its methods are unnecessary
# to reproduce this storage constraint. Dependencies retain their source bytes.
FLOW_TYPES = ['FlowBlockId', 'OwnerSlotId', 'FlowFieldId', 'FlowField', 'FlowNullValue', 'FlowSlot', 'FlowRegion', 'FlowEvent', 'FlowLoan', 'FlowObligation']
