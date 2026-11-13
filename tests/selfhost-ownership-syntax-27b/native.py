#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute current production-compiler targets, C0 oracles and refusal sentinels."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess

from support import execute, output_path, sha, tool_identity, write

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'

LITERALS = '''int main() {
	u64 high = 0xffff_ffff_ffff_ffff;
	i64 low = -0x8000_0000_0000_0000;
	u8 bits = 0b1010_1100;
	int decimal = 8_000_000;
	if (high != 18446744073709551615 || low != -9223372036854775808 || bits != 172 || decimal != 8000000) return 1;
	return 42;
}
'''
ITEM = '''extern(C) void note_drop(int value);
extern(C) int drop_count();
extern(C) int drop_sum();
class Item {
	int value;
	init(int value) { this.value = value; }
	deinit() { note_drop(this.value); }
}
'''
OWNERS = ITEM+'''Item make(int value) { var result = new Item(value); return move result; }
class Holder {
	Item item;
	int[] data;
	init(owned Item incoming) { this.item = move incoming; this.data = new int[2]; }
}
int work() {
	Item first = make(40);
	Holder holder = new Holder(move first);
	return holder.item.value + len(holder.data);
}
int main() {
	int result = work();
	if (drop_count() != 1 || drop_sum() != 40) return 1;
	return result;
}
'''
GENERIC_TRAILING = '''T identity<T,>(T value,) { return value; }
int main() { return identity<int,>(42,); }
'''
ARRAY_RESULT = '''int[] make_values() {
	var values = new int[2];
	values[0] = 40; values[1] = 2;
	return move values;
}
int main() {
	int[] values = make_values();
	return values[0] + values[1];
}
'''
GENERIC_OWNER = ITEM+'''Vector<Item> make() {
	var values = new Vector<Item>(1);
	var item = new Item(42);
	if (!values.append(move item)) return move values;
	return move values;
}
int work() {
	Vector<Item> values = make();
	Item item = values.take(0);
	return item.value;
}
int main() {
	int result = work();
	if (drop_count() != 1 || drop_sum() != 42) return 1;
	return result;
}
'''
FLOAT_COMPOUND = '''int main() {
	f32 small = 20.0f;
	f64 wide = 20.0d;
	small += 22.0f;
	small *= 0.5f;
	small -= 1.0f;
	small /= 2.0f;
	wide += 22.0d;
	wide *= 0.5d;
	wide -= 1.0d;
	wide /= 2.0d;
	if (small != 10.0f || wide != 10.0d) return 1;
	f32 negative_zero = -0.0f;
	negative_zero *= 2.0f;
	if (1.0f / negative_zero >= 0.0f) return 1;
	f64 unordered = 0.0d / 0.0d;
	unordered += 0.0d;
	if (unordered == unordered) return 1;
	return 42;
}
'''

SUGAR = '''int add(int first, int second,) => first+second;
class Count {
	int content;
	init(int value,) { this.content = value; }
	property int length => this.content;
	property int twice { get => this.content*2; }
	int plus(int value,) => this.content+value;
}
int main() {
	Count count = new Count(7,);
	int[2] values = {20,22,};
	return add(values[0], values[1],) + count.length + count.twice + count.plus(1,) - 29;
}
'''
VIEWS = '''extern(C) void* echo_ptr(void* pointer);
extern(C) void* anchor_ptr();
void* raw(void* pointer) => pointer;
int length(int[] view) => len(view);
class RawHolder {
	void* pointer;
	init(void* pointer) { this.pointer = pointer; }
}
int main() {
	int[] content = new int[2];
	void* pointer = anchor_ptr();
	RawHolder holder = new RawHolder(pointer);
	if (pointer == null || echo_ptr(raw(holder.pointer)) != pointer) return 1;
	if (echo_ptr(raw(null)) != null) return 1;
	return length(content) + 40;
}
'''
RECORDS = '''struct Point { int x; int y; }
Point point(int y) => Point {x = 20, y,};
int sum(Point p) { return p.x + p.y; }
int main() { return sum(point(22)); }
'''
CONDITIONAL = '''extern(C) int tick(int value);
extern(C) int tick_count();
int main() {
	int result = tick(1) == 1 ? tick(42) : tick(99);
	int other = tick(0) == 1 ? tick(99) : tick(42);
	if (tick_count() != 4 || result != 42 || other != 42) return 1;
	return result + other - 42;
}
'''
COMPOUND = '''int main() {
	int x = 20;
	x += 22;
	x -= 2;
	x *= 3;
	x /= 3;
	x %= 100;
	x &= 127;
	x |= 0;
	x ^= 2;
	x <<= 1;
	x >>= 1;
	return x;
}
'''
COMPOUND_PLACE = '''extern(C) int tick(int value);
extern(C) int tick_count();
class Box { int value; init(int value) { this.value = value; } }
struct Inner { int value; }
struct Outer { Inner inner; int other; }
int parameter(int x) { x += 2; return x; }
int main() {
	int[] values = new int[1];
	values[0] = 40;
	values[tick(0)] += tick(2);
	Box box = new Box(40);
	box.value += 2;
	Outer point = {inner = {value = 40}, other = 9};
	point.inner.value += 2;
	if (tick_count() != 2 || values[0] != 42 || box.value != 42 || point.other != 9 || point.inner.value != 42) return 1;
	return parameter(40);
}
'''

CRC = '''struct Digest { u32 crc; int count; }
u32 crc32(u8[] bytes) {
	u32 state = 0xffff_ffff;
	int i = 0;
	while (i < len(bytes)) {
		state ^= bytes[i] as u32;
		int bit = 0;
		while (bit < 8) {
			if ((state & 1) == 1) {
				state >>= 1;
				state ^= 0xedb8_8320;
			} else {
				state >>= 1;
			}
			bit += 1;
		}
		i += 1;
	}
	return state ^ 0xffff_ffff;
}
Digest digest(u8[] bytes) {
	int count = len(bytes);
	return Digest {crc = crc32(bytes), count,};
}
int main() {
	var bytes = new u8[9];
	bytes[0] = 49; bytes[1] = 50; bytes[2] = 51;
	bytes[3] = 52; bytes[4] = 53; bytes[5] = 54;
	bytes[6] = 55; bytes[7] = 56; bytes[8] = 57;
	var value = digest(bytes);
	if (value.crc != 0xcbf4_3926) return 1;
	return value.count + 33;
}
'''
ERROR_RESULT = ITEM+'''Item fallible(bool fail) throws Error {
	if (fail) {
		throw new Error("factory failed");
	}
	var item = new Item(40);
	return move item;
}
int work(bool fail) {
	try {
		Item item = fallible(fail);
		return item.value + 2;
	} catch (Error error) {
		return 42;
	}
}
int main() {
	int success = work(false);
	int failure = work(true);
	if (drop_count() != 1 || drop_sum() != 40 || success != 42 || failure != 42) return 1;
	return success;
}
'''
PARTIAL_FIELD = ITEM+'''Item make_piece(bool fail) throws Error {
	if (fail) { throw new Error("partial factory"); }
	var item = new Item(2);
	return move item;
}
Item empty_piece() { return null; }
class Holder {
	Item first;
	Item second;
	init(owned Item incoming) {
		this.first = move incoming;
		this.second = empty_piece();
	}
	void finish(bool fail) throws Error {
		var next = make_piece(fail);
		this.second = move next;
	}
}
int attempt(bool fail) {
	var item = new Item(40);
	try { var holder = new Holder(move item); holder.finish(fail); }
	catch (Error error) { return 42; }
	return 42;
}
int main() {
	if (attempt(false) != 42 || drop_count() != 2 || drop_sum() != 42) return 1;
	if (attempt(true) != 42 || drop_count() != 3 || drop_sum() != 82) return 1;
	return 42;
}
'''

CONDITIONAL_OWNER = ITEM+'''Item choose(bool first) {
	var left = new Item(40);
	var right = new Item(2);
	return first ? move left : move right;
}
Item choose_new(bool first) {
	return first ? new Item(20) : new Item(22);
}
Item choose_absent(bool empty) {
	return empty ? null : new Item(2);
}
int fresh(bool first) {
	Item selected = choose_new(first);
	return selected.value;
}
int optional(bool empty) {
	Item selected = choose_absent(empty);
	if (selected == null) return 40;
	return selected.value + 38;
}
int work(bool first) {
	Item chosen = choose(first);
	if (first) {
		if (drop_count() != 1 || drop_sum() != 2) return 1;
		return chosen.value + 2;
	}
	if (drop_count() != 3 || drop_sum() != 82) return 1;
	return chosen.value + 40;
}
int main() {
	int initial = work(true);
	if (initial != 42) return 1;
	int result = work(false);
	if (drop_count() != 4 || drop_sum() != 84) return 1;
	if (fresh(true) + fresh(false) != 42 || drop_count() != 6 || drop_sum() != 126) return 1;
	if (optional(true) != 40 || optional(false) != 40 || drop_count() != 7 || drop_sum() != 128) return 1;
	return result;
}
'''

WEAK = ITEM+'''int read(Item value) { return value.value; }
int inspect(shared Item value) { return read(shared_borrow(value)); }
Weak<Item> observe() {
	var item = new Item(40);
	Shared<Item> strong = shared_acquire(move item);
	weak shared Item observer = shared_downgrade(strong);
	var duplicate = weak_clone(observer);
	var alive = weak_upgrade(duplicate);
	if (alive != null) { if (inspect(alive) != 40) return null; }
	else { return null; }
	return move observer;
}
int main() {
	var observer = observe();
	var dead = weak_upgrade(observer);
	if (dead != null) return 1;
	if (drop_count() != 1 || drop_sum() != 40) return 2;
	return 42;
}
'''
BORROWED = ITEM+'''class Holder {
	readonly Item root;
	readonly borrowed Item view;
	init(owned Item incoming) { this.root = move incoming; this.view = this.root; }
}
int read(Item value) { return value.value; }
int work() {
	var item = new Item(42);
	var holder = new Holder(move item);
	return read(holder.view);
}
int main() {
	int result = work();
	if (drop_count() != 1 || drop_sum() != 42) return 1;
	return result;
}
'''


def expanded_compounds(text):
	# Independent legacy behavior oracle for these deliberately side-effect-free
	# destinations. The indexed oracle is authored separately below.
	return re.sub(r'(?m)^(\s*)([a-zA-Z_][a-zA-Z_0-9.]*) (<<|>>|[+*/%&|^\-])= ([^;]+);', r'\1\2 = \2 \3 \4;', text)


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('compiler', 'c0', 'build', 'runtime', 'link'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True)
	p.add_argument('--c0-sha256', required=True)
	p.add_argument('--case', action='append', help='Run only named positive cases during focused development; records the selection explicitly')
	p.add_argument('--oracle-only', action='store_true', help='Qualify the authored C0 equivalents only; gives no current-language acceptance credit')
	p.add_argument('--feature', choices=('initial', 'records', 'conditional', 'compound', 'weak', 'borrowed', 'workload', 'errors'), action='append', required=True)
	a = p.parse_args()
	assert all(re.fullmatch('[0-9a-f]{64}', s) for s in (a.compiler_sha256, a.c0_sha256))
	assert sha(a.compiler) == a.compiler_sha256 and sha(a.c0) == a.c0_sha256
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	build = output_path(a.build, WORK/'build')
	runtime = output_path(a.runtime, WORK/'runtime')
	build.mkdir(parents=True, exist_ok=False)
	runtime.mkdir(parents=True, exist_ok=False)
	import json
	link = json.loads(a.link.read_text())
	providers = {path:digest for path, digest in link['objects'].items() if Path(path).name not in ('llvm-capi.o', 'arguments.o')}
	assert len(providers) == 5 and all(sha(path) == digest for path, digest in providers.items())
	bridge = runtime/'bridge.c'
	bridge.write_text('static int drops, sum, ticks, anchor = 42;\nvoid note_drop(int value) { ++drops; sum += value; }\nint drop_count(void) { return drops; }\nint drop_sum(void) { return sum; }\nvoid *echo_ptr(void *pointer) { return pointer; }\nvoid *anchor_ptr(void) { return &anchor; }\nint tick(int value) { ++ticks; return value; }\nint tick_count(void) { return ticks; }\n')
	env = dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')
	env.pop('LD_PRELOAD', None)
	env.pop('VALGRIND_OPTS', None)
	tools = tool_identity([a.compiler, a.c0, '/usr/bin/time', *[shutil.which(n) for n in ('gcc', 'cc', 'as', 'ld', 'opt', 'llc', 'valgrind')]])
	source_inputs = {str(path):sha(path) for path in (Path(__file__), Path(__file__).with_name('support.py'), a.link, bridge)}
	write(runtime/'inputs.json', source_inputs)
	write(runtime/'tools.json', tools)
	commands = []
	def run(name, argv, expected=0, timeout=600):
		argv = list(map(str, argv))
		result = execute(argv, runtime/name, expected=expected, timeout=timeout, env=env)
		commands.append(dict(name=name, argv=argv, result=result))
		write(runtime/'commands.json', commands)
		print(name, result['status'], round(result['seconds'], 3), flush=True)
		assert result['status'] == 'EXPECTED_OUTCOME', (name, result)
	def memory(name, argv, expected):
		run(name, ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *map(str, argv)], expected, 900)
		log = (runtime/name/'stderr').read_bytes()
		assert all(m in log for m in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
	bridge_object = build/'bridge.o'
	run('bridge', ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', bridge, '-o', bridge_object])
	objects = [*providers, str(bridge_object)]
	cases = []
	if 'initial' in a.feature:
		cases += [('literal-widths', LITERALS, LITERALS.replace('0xffff_ffff_ffff_ffff', '18446744073709551615').replace('0x8000_0000_0000_0000', '9223372036854775808').replace('0b1010_1100', '172').replace('8_000_000', '8000000')),
			('owner-fields-factory-local', OWNERS, OWNERS.replace('Item make(', 'owned Item make(').replace('\tItem item;', '\towned Item item;').replace('\tint[] data;', '\towned int[] data;').replace('Item first =', 'var first =').replace('Holder holder =', 'var holder =')),
			('concise-trailing', SUGAR, SUGAR.replace('int add(int first, int second,) => first+second;', 'int add(int first, int second) { return first+second; }').replace('int value,)', 'int value)').replace('int plus(int value) => this.content+value;', 'int plus(int value) { return this.content+value; }').replace('property int length => this.content;', 'property int length { get { return this.content; } }').replace('get => this.content*2;', 'get { return this.content*2; }').replace('Count count =', 'var count =').replace('7,)', '7)').replace('20,22,}', '20,22}').replace('values[1],)', 'values[1])').replace('plus(1,)', 'plus(1)')),
			('views-and-C-pointer', VIEWS, VIEWS.replace('void* raw(void* pointer) => pointer;', 'void* raw(void* pointer) { return pointer; }').replace('int length(int[] view) => len(view);', 'int length(int[] view) { return len(view); }').replace('int[] content =', 'owned int[] content =').replace('RawHolder holder =', 'var holder ='))]
	if 'initial' in a.feature:
		cases.append(('generic-trailing', GENERIC_TRAILING, GENERIC_TRAILING.replace('<T,>', '<T>').replace('T value,)', 'T value)').replace('<int,>', '<int>').replace('42,)', '42)')))
		cases.append(('array-owning-result', ARRAY_RESULT, ARRAY_RESULT.replace('int[] make_values()', 'owned int[] make_values()').replace('int[] values = make_values();', 'var values = make_values();')))
		cases.append(('generic-owning-result', GENERIC_OWNER, GENERIC_OWNER.replace('Vector<Item> make()', 'owned Vector<Item> make()').replace('Vector<Item> values = make();', 'var values = make();').replace('Item item = values.take(0);', 'var item = values.take(0);')))
	if 'records' in a.feature:
		cases.append(('record-punning', RECORDS, 'struct Point { int x; int y; }\nPoint point(int y) { Point p = {x = 20, y = y}; return p; }\nint sum(Point p) { return p.x + p.y; }\nint main() { return sum(point(22)); }\n'))
	if 'conditional' in a.feature:
		cases.append(('lazy-conditional', CONDITIONAL, CONDITIONAL.replace('int result = tick(1) == 1 ? tick(42) : tick(99);', 'int result = 0; if (tick(1) == 1) { result = tick(42); } else { result = tick(99); }').replace('int other = tick(0) == 1 ? tick(99) : tick(42);', 'int other = 0; if (tick(0) == 1) { other = tick(99); } else { other = tick(42); }')))
	if 'conditional' in a.feature:
		legacy_owner = CONDITIONAL_OWNER.replace('Item choose(', 'owned Item choose(').replace('Item choose_new(', 'owned Item choose_new(').replace('Item choose_absent(', 'owned Item choose_absent(').replace('return first ? move left : move right;', 'if (first) return move left; return move right;').replace('return first ? new Item(20) : new Item(22);', 'if (first) { var value = new Item(20); return move value; } var value = new Item(22); return move value;').replace('return empty ? null : new Item(2);', 'if (empty) return null; var value = new Item(2); return move value;').replace('Item chosen =', 'var chosen =').replace('Item selected =', 'var selected =')
		cases.append(('conditional-owner-transfer', CONDITIONAL_OWNER, legacy_owner))
	if 'compound' in a.feature:
		cases.append(('compound-operators', COMPOUND, expanded_compounds(COMPOUND)))
		cases.append(('compound-float', FLOAT_COMPOUND, expanded_compounds(FLOAT_COMPOUND)))
		legacy_places = expanded_compounds(COMPOUND_PLACE).replace('int parameter(int x) { x += 2; return x; }', 'int parameter(int x) { return x+2; }').replace('Box box =', 'var box =').replace('int[] values =', 'owned int[] values =').replace('values[tick(0)] += tick(2);', 'int index = tick(0); int previous = values[index]; int addend = tick(2); values[index] = previous + addend;')
		cases.append(('compound-places', COMPOUND_PLACE, legacy_places))
	if 'weak' in a.feature:
		legacy_weak = WEAK.replace('int inspect(shared Item', 'int inspect(borrowed shared Item').replace('Weak<Item> observe()', 'owned Weak<Item> observe()').replace('Shared<Item> strong =', 'var strong =').replace('weak shared Item observer =', 'var observer =')
		cases.append(('weak-death-upgrade', WEAK, legacy_weak))
	if 'borrowed' in a.feature:
		# The legacy oracle reads the same readonly owner directly. The modern
		# target must prove, store, load and use its distinct borrowed field.
		legacy_borrow = BORROWED.replace('readonly Item root;', 'owned Item root;').replace('\treadonly borrowed Item view;\n', '').replace(' this.view = this.root;', '').replace('read(holder.view)', 'read(holder.root)')
		cases.append(('stored-borrow-sibling', BORROWED, legacy_borrow))
	if 'workload' in a.feature:
		legacy_crc = expanded_compounds(CRC).replace('0xffff_ffff', '4294967295').replace('0xedb8_8320', '3988292384').replace('0xcbf4_3926', '3421780262').replace('return Digest {crc = crc32(bytes), count,};', 'Digest result = {crc = crc32(bytes), count = count}; return result;')
		cases.append(('crc-record-workload', CRC, legacy_crc))
	if 'errors' in a.feature:
		cases.append(('owning-error-result', ERROR_RESULT, ERROR_RESULT.replace('Item fallible(', 'owned Item fallible(').replace('Item item = fallible', 'var item = fallible')))
		cases.append(('partial-field-error', PARTIAL_FIELD, PARTIAL_FIELD.replace('Item make_piece(', 'owned Item make_piece(').replace('Item empty_piece(', 'owned Item empty_piece(').replace('\tItem first;', '\towned Item first;').replace('\tItem second;', '\towned Item second;')))
	if a.case:
		assert set(a.case).issubset({case[0] for case in cases})
		cases = [case for case in cases if case[0] in a.case]
	products = {str(bridge_object):sha(bridge_object)}
	for name, modern, legacy in cases:
		source = runtime/(name+'.astra')
		oracle_source = runtime/(name+'-legacy.astra')
		source.write_text('language astra27b;\n'+modern)
		oracle_source.write_text(legacy)
		identity = {str(path):sha(path) for path in (source, oracle_source)}
		source_inputs.update(identity)
		write(runtime/'inputs.json', source_inputs)
		extra_sources = []
		if name == 'generic-owning-result':
			extra_sources = [ROOT/'lib/astra/collections/vector.astra']
		if name in ('owning-error-result', 'partial-field-error'):
			extra_sources = [ROOT/'lib/astra/base/errors.astra', ROOT/'lib/astra/hosted/text.astra']
		if extra_sources:
			source_inputs.update({str(path):sha(path) for path in extra_sources})
			write(runtime/'inputs.json', source_inputs)
		oracle = build/(name+'-C0')
		links = [arg for path in objects for arg in ('--link-object', path)]
		run(name+'-C0-build', [a.c0, '-O0', oracle_source, *extra_sources, *links, '-o', oracle])
		run(name+'-C0-native', [oracle], 42)
		products[str(oracle)] = sha(oracle)
		write(runtime/'products.json', products)
		if a.oracle_only:
			continue
		for mode in ('O0', 'O2'):
			obj = build/(name+'-'+mode+'.o')
			target = build/(name+'-'+mode)
			run(name+'-'+mode+'-compile', [a.compiler, '-c', '-'+mode, '-o', obj, source, *extra_sources])
			run(name+'-'+mode+'-link', ['cc', '-no-pie', obj, *objects, '-o', target])
			run(name+'-'+mode+'-native', [target], 42)
			memory(name+'-'+mode+'-memory', [target], 42)
			products[str(target)] = sha(target)
			products[str(obj)] = sha(obj)
			write(runtime/'products.json', products)
		memory(name+'-compiler-memory', [a.compiler, '--emit-llvm', '-o', build/(name+'-memory.ll'), source, *extra_sources], 0)
		products[str(build/(name+'-memory.ll'))] = sha(build/(name+'-memory.ll'))
		write(runtime/'products.json', products)
		assert all(sha(path) == digest for path, digest in identity.items())
	negative = [('numeric-overflow', 'int main() { u8 value = 0x100; return value as int; }'), ('borrow-consume', ITEM+'int consume(owned Item item) { return item.value; } int inspect(Item item) { return consume(move item); } int main() { var item = new Item(42); return inspect(item); }'), ('double-move', ITEM+'int consume(owned Item item) { return item.value; } int main() { var item = new Item(21); return consume(move item)+consume(move item); }')]
	if 'errors' in a.feature:
		negative.append(('wrong-owning-result', ITEM+'Item bad(Item value) { return value; } int main() { var item = new Item(42); var other = bad(item); return other.value; }'))
	if 'records' in a.feature:
		negative += [('record-missing', 'struct Point { int x; int y; } int main() { var p = Point {x = 42}; return p.x; }'), ('record-duplicate', 'struct Point { int x; int y; } int main() { var p = Point {x = 42, x = 1}; return p.x; }'), ('record-owner-pun', ITEM+'struct Pack { owned Item item; } int main() { var item = new Item(42); var pack = Pack {item}; return 42; }')]
	if 'conditional' in a.feature:
		negative += [('conditional-type', 'int main() { return true ? 42 : false; }'), ('conditional-condition', 'int main() { return 1 ? 42 : 0; }'), ('conditional-owner-alias', ITEM+'int main() { var owner = new Item(42); Item other = true ? move owner : owner; return other.value; }')]
	if 'compound' in a.feature:
		negative += [('compound-narrowing', 'int main() { u8 x = 1; int y = 2; x += y; return x as int; }'), ('compound-float-remainder', 'int main() { f64 x = 42.0d; x %= 2.0d; return x as int; }'), ('compound-not-place', 'int value() { return 40; } int main() { value() += 2; return 42; }')]
	if 'weak' in a.feature:
		negative += [('weak-unique', ITEM+'int main() { var item = new Item(42); weak Item observer = item; return 42; }'),
			('weak-unguarded', ITEM+'int read(Item value) { return value.value; } int main() { var item = new Item(42); var strong = shared_acquire(move item); var observer = shared_downgrade(strong); var upgraded = weak_upgrade(observer); return read(shared_borrow(upgraded)); }'),
			('modern-shared-borrow-consume', ITEM+'void consume(owned shared Item value) { } void inspect(shared Item value) { consume(move value); } int main() { var item = new Item(42); var strong = shared_acquire(move item); inspect(strong); return 42; }')]
	if 'borrowed' in a.feature:
		negative += [('stored-borrow-external', ITEM+'class Holder { readonly borrowed Item view; init(Item incoming) { this.view = incoming; } } int main() { var item = new Item(42); var holder = new Holder(item); return holder.view.value; }'),
			('stored-borrow-order', BORROWED.replace('this.root = move incoming; this.view = this.root;', 'this.view = this.root; this.root = move incoming;')),
			('stored-borrow-replace', BORROWED.replace('return read(holder.view);', 'holder.view = holder.root; return 42;')),
			('borrow-after-move', ITEM+'int inspect(Item value) { return value.value; } void consume(owned Item value) { } int main() { var root = new Item(42); Item view = root; consume(move root); return inspect(view); }'),
			('raw-owner-adoption', ITEM+'extern(C) void* echo_ptr(void* value); int main() { Item item = echo_ptr(null) as Item; return item.value; }')]
	if a.oracle_only:
		negative = []
	for name, text in negative:
		source = runtime/(name+'.astra')
		source.write_text('language astra27b;\n'+text+'\n')
		source_inputs[str(source)] = sha(source)
		write(runtime/'inputs.json', source_inputs)
		target = build/(name+'.ll')
		target.write_bytes(b'ASTRA27B refusal sentinel\n')
		digest = sha(target)
		run(name+'-reject', [a.compiler, '--emit-llvm', '-o', target, source], 1)
		assert sha(target) == digest and (runtime/(name+'-reject')/'stderr').read_bytes()
	assert sha(a.compiler) == a.compiler_sha256 and sha(a.c0) == a.c0_sha256
	assert all(sha(path) == digest for path, digest in tools.items())
	assert all(sha(path) == digest for path, digest in source_inputs.items())
	assert all(sha(path) == digest for path, digest in products.items())
	write(runtime/'result.json', dict(status='C0_ORACLES_ONLY' if a.oracle_only else 'SELECTED_CURRENT_COMPILER_NATIVE_GATES_PASS', oracle_only=a.oracle_only, selected_cases=[case[0] for case in cases], features=a.feature, compiler=dict(path=str(a.compiler), sha256=a.compiler_sha256), tools=tools, providers=providers, source_inputs=source_inputs, inputs_sha256=sha(runtime/'inputs.json'), products=products, commands_sha256=sha(runtime/'commands.json'), scope='Selected feature programs and source refusals only. Remaining ownership/syntax, physical mutations, full preservation and delivery gates are separate.'))
	print('C0_ORACLES_ONLY' if a.oracle_only else 'SELECTED_CURRENT_COMPILER_NATIVE_GATES_PASS', flush=True)


if __name__ == '__main__':
	main()
