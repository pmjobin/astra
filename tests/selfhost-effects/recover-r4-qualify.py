#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fielded Class witnesses with C0 observables and genuine discarded calls."""
import sys
from state import ROOT, load_module

VAULT = '''class Vault {
	private owned int[] data;
	private int count;
	private bool enabled;
	init(owned int[] data, int count) { this.data = move data; this.count = count; this.enabled = false; }
	int value() { if (this.enabled) return 3; return this.count + len(this.data); }
	bool touch(bool fail) throws Error { this.count = this.count + 1; if (fail) { throw new Error("kept"); } return false; }
	void replace(owned int[] data) { this.data = move data; }
}
'''


def corpus():
	def owner(count, size=1): return 'var data = new int['+str(size)+']; var value = new Vault(move data, '+str(count)+'); '
	def observed(before, expression):
		return 'int main() { '+before+'try { '+expression+' return 3; } catch (Error caught) { if (caught.message != "kept") return 4; return value.value(); } }\n'
	rows = {
		'field-five-member-layout-success': 'class Label { private readonly string text; init(string text) { this.text = text; } property string value { get { return this.text; } } } class Frame { private owned Label title; private owned u8[] bytes; private owned int[] offsets; private int count; private bool flag; init(owned Label title, owned u8[] bytes, owned int[] offsets, int count, bool flag) { this.title = move title; this.bytes = move bytes; this.flag = flag; this.offsets = move offsets; this.count = count; } int value() { if (this.flag) return 3; return this.count + len(this.bytes) + len(this.offsets); } } int main() { var title = new Label("kept"); var bytes = new u8[1]; var offsets = new int[1]; var frame = new Frame(move title, move bytes, move offsets, 40, false); return frame.value(); }\n',
		'field-scalar-and-length-properties-success': 'class Metrics { private owned int[] data; private int bias; private bool flag; init(owned int[] data) { this.data = move data; this.bias = 40; this.flag = false; } property int length { get { return len(this.data); } } property int score { get { return this.bias; } } property bool active { get { return this.flag; } } } int main() { var data = new int[2]; var value = new Metrics(move data); if (value.active) return 3; return value.score + value.length; }\n',
		'field-static-string-discard-success': 'class Counter { private int count; init() { this.count = 41; } string ignored() { this.count = this.count + 1; return "discarded"; } int value() { return this.count; } } int main() { var value = new Counter(); value.ignored(); return value.value(); }\n',
		'field-Class-factory-replacement-success': 'class Item { private int value; init(int value) { this.value = value; } int number() { return this.value; } } int inspect(Item item) { return item.number(); } owned Item make() { var result = new Item(42); return move result; } class Box { private owned Item item; init(owned Item item) { this.item = move item; } void replace() { this.item = make(); } int value() { return inspect(this.item); } } int main() { var item = new Item(3); var box = new Box(move item); box.replace(); return box.value(); }\n',
		'field-Class-factory-error-preserves-old': 'class Item { private int value; init(int value) { this.value = value; } int number() { return this.value; } } int inspect(Item item) { return item.number(); } owned Item make(bool fail) throws Error { if (fail) { throw new Error("kept"); } var result = new Item(17); return move result; } class Box { private owned Item item; init(owned Item item) { this.item = move item; } void replace(bool fail) throws Error { this.item = make(fail); } int value() { return inspect(this.item); } } int main() { var item = new Item(42); var box = new Box(move item); try { box.replace(true); return 3; } catch (Error caught) { if (caught.message != "kept") return 4; return box.value(); } }\n',
		'field-Class-checked-factory-success': 'class Item { private int value; init(int value) { this.value = value; } int number() { return this.value; } } int inspect(Item item) { return item.number(); } owned Item make(bool fail) throws Error { if (fail) { throw new Error("kept"); } var result = new Item(17); return move result; } class Box { private owned Item item; init(owned Item item) { this.item = move item; } void replace(bool fail) throws Error { this.item = make(fail); } int value() { return inspect(this.item); } } int main() { var item = new Item(3); var box = new Box(move item); try { box.replace(false); return box.value() + 25; } catch (Error caught) { return 4; } }\n',
		'field-mixed-layout-success': VAULT+'int main() { '+owner(1, 41)+'return value.value(); }\n',
		'field-empty-buffer-success': VAULT+'int main() { '+owner(42, 0)+'return value.value(); }\n',
		'field-buffer-replacement-success': VAULT+'int main() { '+owner(0, 3)+'var replacement = new int[42]; value.replace(move replacement); return value.value(); }\n',
		'field-owned-child-success': 'class Label { readonly string snapshot; init(string text) { this.snapshot = text; } property string text { get { return this.snapshot; } } }\nclass Bundle { private owned Label label; private bool flag; private owned int[] data; private int count; init(owned Label label, owned int[] data) { this.label = move label; this.flag = false; this.data = move data; this.count = 40; } int value() { if (this.flag) return 3; return this.count + len(this.data); } }\nint main() { var label = new Label("original bytes"); var data = new int[2]; var value = new Bundle(move label, move data); return value.value(); }\n',
		'field-discard-checked-error': VAULT+observed(owner(40), 'value.touch(true);'),
		'field-discard-false-then-error': VAULT+observed(owner(39), 'value.touch(false); value.touch(true);'),
		'field-discard-propagation-error': VAULT+'bool relay(Vault value) throws Error { return value.touch(true); }\n'+observed(owner(40), 'relay(value);'),
		'field-discard-rethrow-error': VAULT+'void relay(Vault value) throws Error { try { value.touch(true); } catch (Error caught) { throw; } }\n'+observed(owner(40), 'relay(value);'),
		'field-argument-abort-error': VAULT+'bool explode(Vault value) throws Error { return value.touch(true); } void consume(owned int[] data, bool flag) {}\n'+observed(owner(40)+'var spare = new int[7]; ', 'consume(move spare, explode(value));'),
		'field-owned-input-error': VAULT+'bool consume(owned Vault value) throws Error { value.touch(true); return false; }\nint main() { '+owner(40)+'try { consume(move value); return 3; } catch (Error caught) { if (caught.message == "kept") return 42; return 4; } }\n',
		'field-replacement-then-error': VAULT+observed(owner(40, 9)+'var replacement = new int[1]; ', 'value.replace(move replacement); value.touch(true);'),
		'field-loop-discard-error': VAULT+'void replay(Vault value) throws Error { int i = 0; while (i < 2) { value.touch(i == 1); i = i + 1; } }\n'+observed(owner(39), 'replay(value);'),
	}
	assert len(rows) == len(set(rows.values())) == 18
	return rows


def main():
	if '--oracle-only' in sys.argv:
		runner = load_module('r4_field_oracles', ROOT/'tests/selfhost-effects/recover-frontier.py'); runner.corpus = corpus; runner.main(); return
	runner = load_module('r4_field_native', ROOT/'tests/selfhost-effects/recover-qualify.py'); runner.expanded_corpus = corpus; sys.argv += ['--expanded']; runner.main()


if __name__ == '__main__':
	main()
