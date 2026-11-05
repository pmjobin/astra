#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Distinct slot/record programs and an exact, disclosed whole-method view."""
import argparse
import json
from state import ROOT, RUNTIME, sha

RECORD = '''struct Ticket { int code; }
struct Parcel { Ticket identity; i64 weight; bool ready; }
'''
DEPOT = RECORD+'''class Depot {
	owned Parcel[] primary;
	owned Parcel[] reserve;
	init() { this.primary = new Parcel[3]; this.reserve = new Parcel[7]; }
	void grow(int size) { var next = new Parcel[size]; next[0] = this.primary[0]; swap(this.primary, next); }
}
'''
SEED = 'Parcel x = {identity = {code = 19}, weight = 123456789, ready = true}; Parcel y = {identity = {code = 31}, weight = 987654321, ready = false};'


def declaration(path, name):
	raw = (ROOT/path).read_bytes(); start = raw.index(name.encode()); end = raw.index(b'\n}', start)+2
	return raw[start:end]+b'\n'


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', default='v1'); args = p.parse_args()
	assert args.version.replace('-', '').isalnum()
	leaf = RUNTIME/('corpus-'+args.version); leaf.mkdir(exist_ok=False)
	cases = {
		'nested-local-pair': (RECORD+'int main() { '+SEED+' var a = new Parcel[2]; var b = new Parcel[5]; a[1] = x; b[4] = y; swap(a, b); if (len(a) != 5 || len(b) != 2 || a[4].identity.code != 31 || b[1].weight != 123456789 || a[4].ready) return 99; return 41; }\n', 41),
		'nested-field-local': (DEPOT+'int main() { '+SEED+' var box = new Depot(); box.primary[0] = x; var next = new Parcel[11]; next[10] = y; swap(box.primary, next); if (len(next) != 3 || len(box.primary) != 11 || next[0].identity.code != 19 || box.primary[10].weight != 987654321) return 99; return 42; }\n', 42),
		'nested-field-field': (DEPOT+'int main() { '+SEED+' var box = new Depot(); box.primary[2] = x; box.reserve[6] = y; swap(box.primary, box.reserve); if (len(box.primary) != 7 || len(box.reserve) != 3 || box.primary[6].identity.code != 31 || !box.reserve[2].ready) return 99; return 43; }\n', 43),
		'nested-alias': (DEPOT+'int alias(borrowed Depot left, borrowed Depot right) { swap(left.primary, right.primary); return len(left.primary); }\nint main() { '+SEED+' var box = new Depot(); box.primary[0] = x; if (alias(box, box) != 3 || box.primary[0].weight != 123456789) return 99; return 44; }\n', 44),
		'nested-owner-parameter': (RECORD+'owned Parcel[] exchange(owned Parcel[] a, owned Parcel[] b) { swap(a, b); return move a; }\nint main() { '+SEED+' var a = new Parcel[1]; var b = new Parcel[9]; b[8] = y; var c = exchange(move a, move b); if (len(c) != 9 || c[8].identity.code != 31) return 99; return 45; }\n', 45),
		'nested-empty-field': (DEPOT+'int main() { '+SEED+' var box = new Depot(); box.primary[0] = x; var empty = new Parcel[0]; swap(empty, box.primary); swap(box.reserve, box.reserve); if (len(box.primary) != 0 || len(empty) != 3 || empty[0].identity.code != 19) return 99; return 46; }\n', 46),
		'nested-return-paths': (DEPOT+'int turn(borrowed Depot box, bool early) { var temp = new Parcel[6]; swap(box.primary, temp); if (early) return len(temp); swap(box.reserve, temp); return len(temp); }\nint main() { var box = new Depot(); if (turn(box, true) != 3 || turn(box, false) != 7 || len(box.reserve) != 6) return 99; return 47; }\n', 47),
		'nested-loop-growth': (DEPOT+'int main() { '+SEED+' var box = new Depot(); box.primary[0] = x; int i = 4; while (i < 12) { box.grow(i); if (len(box.primary) != i || box.primary[0].weight != 123456789) return 99; i = i + 1; } return 48; }\n', 48),
		'nested-rearm': (RECORD+'int main() { '+SEED+' var a = new Parcel[2]; var b = new Parcel[8]; b[7] = y; swap(a, b); var c = move a; a = new Parcel[4]; a[3] = x; if (len(c) != 8 || len(b) != 2 || c[7].weight != 987654321 || a[3].identity.code != 19) return 99; return 49; }\n', 49),
		'nested-cross-object': (DEPOT+'int main() { '+SEED+' var left = new Depot(); var right = new Depot(); left.primary[2] = x; right.reserve[6] = y; swap(left.primary, right.reserve); if (len(left.primary) != 7 || len(right.reserve) != 3 || left.primary[6].identity.code != 31 || !right.reserve[2].ready) return 99; return 50; }\n', 50),
		'generic-nested-owner': (RECORD+'''class Warehouse<T> {
	owned T[] goods;
	init() { this.goods = new T[2]; }
	void replace() { var next = new T[13]; next[0] = this.goods[0]; swap(this.goods, next); }
}
int main() { '''+SEED+' var box = new Warehouse<Parcel>(); box.goods[0] = x; box.replace(); if (len(box.goods) != 13 || box.goods[0].identity.code != 19 || !box.goods[0].ready) return 99; return 51; }\n', 51),
		'nested-snapshot-survival': (DEPOT+'int main() { '+SEED+' var box = new Depot(); box.primary[0] = x; Parcel saved = box.primary[0]; var next = new Parcel[1]; next[0] = y; swap(box.primary, next); if (saved.identity.code != 19 || saved.weight != 123456789 || box.primary[0].identity.code != 31 || next[0].identity.code != 19) return 99; return 52; }\n', 52),
	}
	selection = []
	for name, (source, expected) in cases.items():
		path = leaf/(name+'.astra'); path.write_text(source)
		selection.append(dict(name=name, sources=[dict(path=str(path), bytes=path.stat().st_size, sha256=sha(path))], expected_exit=expected, oracle='Independent explicit length, row field and path assertions; manually specified return value'))
	original = ROOT/'compiler/semantic/checked.astra'; raw = original.read_bytes()
	start = raw.index(b'\tvoid add_signature('); end = raw.index(b'\n\tbool validate()', start)
	view = bytearray(b if b == 10 else 32 for b in raw)
	view[start:end] = raw[start:end]
	begin = raw.index(b'class CheckedIndex {')
	prefix = b'class CheckedIndex {\n\towned CheckedSignature[] signatures;\n\towned SignatureId[] symbol_signatures;\n\tint signature_count;\n\tinit() { this.signatures = new CheckedSignature[16]; this.symbol_signatures = new SignatureId[80]; this.signature_count = 0; }\n'
	assert begin+len(prefix) < start
	view[begin:begin+len(prefix)] = prefix; view[end:end+2] = b'\n}'
	path = leaf/'CheckedIndex-view.astra'; path.write_bytes(view)
	assert path.read_bytes()[start:end] == raw[start:end]
	provider = leaf/'checked-dependencies.astra'
	data = b''.join(declaration(p, name) for p, name in [('compiler/semantic/model.astra','struct SymbolId {'), ('compiler/semantic/types.astra','struct TypeId {'), ('compiler/semantic/types.astra','struct SignatureId {'), ('compiler/semantic/types.astra','struct CheckedSignature {'), ('compiler/syntax/arena-support.astra','int syntax_grown_capacity(')])
	# The capacity helper's assertion binding is explicit and preserves its body.
	data += b'void assert_that(bool value) { if (!value) { var none = new int[0]; int impossible = none[1]; } }\n'
	provider.write_bytes(data)
	entry = leaf/'checked-main.astra'; entry.write_text('''int row_error(borrowed CheckedIndex index, int i) {
	CheckedSignature row = index.signatures[i];
	return (row.declaration.index - i - 1) | (row.callable.index - 1000 - i) | (row.error.index - 2000 - i) | (row.flags - i - 3) | (row.dispatch - i - 5) | (index.symbol_signatures[i + 1].index - i - 1);
}

int main() {
	var index = new CheckedIndex(); int i = 0; int errors = 0;
	while (i < 65) {
		SymbolId symbol = {index = i + 1}; TypeId callable = {index = 1000 + i}; TypeId error = {index = 2000 + i};
		index.add_signature(symbol, callable, error, i + 3, i + 5);
		errors = errors | (index.signature_count - i - 1);
		if (i == 14) errors = errors | (len(index.signatures) - 16);
		if (i == 15) errors = errors | (len(index.signatures) - 16);
		if (i == 16) errors = errors | (len(index.signatures) - 32);
		i = i + 1;
	}
	if (len(index.signatures) != 128) return 93;
	i = 0;
	while (i < 65) {
		errors = errors | row_error(index, i);
		i = i + 1;
	}
	if (errors != 0) return 99;
	return 53;
}
''')
	selection.append(dict(name='original-add-signature', sources=[dict(path=str(p), bytes=p.stat().st_size, sha256=sha(p)) for p in (provider,path,entry)], expected_exit=53, oracle='65 unchanged-method appends, 15/16/17 and repeated growth to 128, all five row fields and symbol signature IDs', view=dict(original=str(original), original_sha256=sha(original), method_span=[start,end], difference='Other Class fields and methods blanked; bounded constructor and exact storage fields replace Class header; original nominal record declarations and complete capacity helper copied; explicit local assert binding. Full CheckedIndex is not qualified.')))
	(leaf/'selection.json').write_text(json.dumps(selection, indent=2)+'\n')
	print(len(selection), 'distinct new source programs; exact add_signature span', start, end)


if __name__ == '__main__':
	main()
