#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent source expectations fixed before TEXTCLASS implementation."""
NOTE = '''class Note {
	readonly string payload;
	init(string input) { this.payload = input; }
	property string text { get { return this.payload; } }
}
'''
CASES = [
	('equal-identities', NOTE, 'int main() { var a = new Note("été"); var b = new Note("été"); if (a == b || a.text != b.text) return 90; return 1; }', 1),
	('counted-nul', NOTE, 'int main() { var a = new Note("a\\0é"); if (a.text != "a\\0é" || a.text == "a") return 90; return a.text.byte_length; }', 4),
	('empty-text', NOTE, 'int main() { var a = new Note(""); if (a.text != "") return 90; return a.text.byte_length; }', 0),
	('bag-grow', NOTE, '''int main() {
	var bag = new Bag<Note>(); int i = 0;
	while (i < 5) { bool room = bag.reserve(i + 1); var a = new Note("é"); bag.append(move a); i = i + 1; }
	var middle = bag.take(1); var tail = bag.take(3);
	if (middle == tail || middle.text != "é" || tail.text != "é") return 90;
	return middle.text.byte_length + tail.text.byte_length + bag.count();
}''', 7),
	('bag-replace', NOTE, 'int main() { var bag = new Bag<Note>(); bool room = bag.reserve(1); var a = new Note("old"); bag.append(move a); var b = new Note("新"); bag.replace(0, move b); var result = bag.take(0); if (result.text != "新") return 90; return result.text.byte_length; }', 3),
	('bag-reserve', NOTE, 'int main() { var bag = new Bag<Note>(); if (!bag.reserve(7) || bag.reserve(-1)) return 90; var a = new Note("ok"); bag.append(move a); if (!bag.reserve(12)) return 91; var b = bag.take(0); if (b.text != "ok") return 92; return bag.capacity() + b.text.byte_length; }', 14),
	('independent-snapshot', NOTE, 'int main() { var a = new Note("abc"); var b = new Note(a.text); release a; if (b.text != "abc") return 90; return b.text.byte_length; }', 3),
	('owner-relay', NOTE+'''owned Note make(string input) { var a = new Note(input); return move a; }
int consume(owned Note input) { if (input.text != "🙂") return 90; return input.text.byte_length; }
''', 'int main() { var a = make("🙂"); return consume(move a); }', 4),
	('early-return', NOTE+'''int use(bool early) { var bag = new Bag<Note>(); bool room = bag.reserve(1); var a = new Note("early"); bag.append(move a); if (early) return bag.count(); var b = bag.take(0); return b.text.byte_length; }
''', 'int main() { return use(true) + use(false); }', 6),
	('move-then-borrow', NOTE+'int use(owned Note input) { var bag = new Bag<Note>(); bool room = bag.reserve(1); bag.append(move input); var b = bag.take(0); if (b.text != "moved") return 90; return b.text.byte_length; }\n', 'int main() { var a = new Note("moved"); return use(move a); }', 5),
	('two-fields', '''class Pair {
	readonly string left;
	readonly string right;
	int tag;
	init(string left, string right, int tag) { this.left = left; this.right = right; this.tag = tag; }
	property string text { get { return this.right; } }
	int get() { return this.tag; }
}
''', 'int main() { var bag = new Bag<Pair>(); bool room = bag.reserve(1); var a = new Pair("left", "右", 8); bag.append(move a); var b = bag.take(0); if (b.text != "右") return 90; return b.get() + b.text.byte_length; }', 11),
	('cross-file', NOTE+'owned Note provide(string input) { var a = new Note(input); return move a; }\n', 'int main() { var a = provide("cross"); var bag = new Bag<Note>(); bool room = bag.reserve(1); bag.append(move a); var b = bag.take(0); return b.text.byte_length; }', 5),
]
NEGATIVES = [
	('readonly-write', NOTE, 'int main() { var a = new Note("a"); a.payload = "b"; return 0; }'),
	('moved-owner', NOTE, 'int main() { var a = new Note("a"); var bag = new Bag<Note>(); bool room = bag.reserve(1); bag.append(move a); return a.text.byte_length; }'),
	('double-release', NOTE, 'int main() { var a = new Note("a"); release a; release a; return 0; }'),
	('borrow-escape', NOTE, 'string escape() { var a = new Note("a"); return a.text; }\nint main() { return escape().byte_length; }'),
	('alias-owner', NOTE, 'int main() { var a = new Note("a"); owned Note b = a; return 0; }'),
	('uninitialized-field', 'class Note { readonly string payload; init(string input) {} }\n', 'int main() { var a = new Note("a"); return 0; }'),
]

# Later allocation-boundary controls remain distinct from the initial corpus.
ADDITIONS = [
	('empty-copy', NOTE, 'int main() { var a = new Note(""); var b = new Note(a.text); release a; if (b.text != "") return 90; return b.text.byte_length; }', 0),
	('one-byte', NOTE, 'int main() { var a = new Note("x"); if (a.text != "x") return 90; return a.text.byte_length; }', 1),
	('text-record-layout', '''struct Row { bool flag; f64 weight; int value; }
class Decorated {
	readonly string payload;
	Row metadata;
	init(string input, Row metadata) { this.payload = input; this.metadata = metadata; }
	property string text { get { return this.payload; } }
	int check() { if (!this.metadata.flag || this.metadata.weight != 2.5) return 90; return this.metadata.value; }
}
''', 'int main() { Row row = {flag = true, weight = 2.5, value = 19}; var bag = new Bag<Decorated>(); bool room = bag.reserve(1); var a = new Decorated("record", row); bag.append(move a); var b = bag.take(0); if (b.text != "record") return 91; return b.check() + b.text.byte_length; }', 25),
]
