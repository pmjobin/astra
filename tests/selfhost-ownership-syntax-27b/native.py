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
SUGAR = '''int add(int first, int second,) => first+second;
class Count {
	int content;
	init(int value,) { this.content = value; }
	property int length => this.content;
	property int twice { get => this.content*2; }
}
int main() {
	Count count = new Count(7,);
	int[2] values = {20,22,};
	return add(values[0], values[1],) + count.length + count.twice - 21;
}
'''
VIEWS = '''extern(C) void* echo_ptr(void* pointer);
void* raw(void* pointer) => pointer;
int length(int[] view) => len(view);
int main() {
	int[] content = new int[2];
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
	if (tick_count() != 2) return 1;
	return result;
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
	p.add_argument('--feature', choices=('initial', 'records', 'conditional', 'compound'), action='append', required=True)
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
	bridge.write_text('static int drops, sum, ticks;\nvoid note_drop(int value) { ++drops; sum += value; }\nint drop_count(void) { return drops; }\nint drop_sum(void) { return sum; }\nvoid *echo_ptr(void *pointer) { return pointer; }\nint tick(int value) { ++ticks; return value; }\nint tick_count(void) { return ticks; }\n')
	env = dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')
	env.pop('LD_PRELOAD', None)
	env.pop('VALGRIND_OPTS', None)
	tools = tool_identity([a.compiler, a.c0, '/usr/bin/time', *[shutil.which(n) for n in ('gcc', 'cc', 'as', 'ld', 'opt', 'llc', 'valgrind')]])
	source_inputs = {str(path):sha(path) for path in (Path(__file__), Path(__file__).with_name('support.py'), a.link, bridge)}
	write(runtime/'inputs.json', source_inputs)
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
			('concise-trailing', SUGAR, SUGAR.replace('int add(int first, int second,) => first+second;', 'int add(int first, int second) { return first+second; }').replace('int value,)', 'int value)').replace('property int length => this.content;', 'property int length { get { return this.content; } }').replace('get => this.content*2;', 'get { return this.content*2; }').replace('Count count =', 'var count =').replace('7,)', '7)').replace('20,22,}', '20,22}').replace('values[1],)', 'values[1])')),
			('views-and-C-pointer', VIEWS, VIEWS.replace('void* raw(void* pointer) => pointer;', 'void* raw(void* pointer) { return pointer; }').replace('int length(int[] view) => len(view);', 'int length(int[] view) { return len(view); }').replace('int[] content =', 'owned int[] content ='))]
	if 'records' in a.feature:
		cases.append(('record-punning', RECORDS, 'struct Point { int x; int y; }\nPoint point(int y) { Point p = {x = 20, y = y}; return p; }\nint sum(Point p) { return p.x + p.y; }\nint main() { return sum(point(22)); }\n'))
	if 'conditional' in a.feature:
		cases.append(('lazy-conditional', CONDITIONAL, CONDITIONAL.replace('int result = tick(1) == 1 ? tick(42) : tick(99);', 'int result = 0; if (tick(1) == 1) { result = tick(42); } else { result = tick(99); }')))
	if 'compound' in a.feature:
		cases.append(('compound-operators', COMPOUND, expanded_compounds(COMPOUND)))
		legacy_places = expanded_compounds(COMPOUND_PLACE).replace('int parameter(int x) { x += 2; return x; }', 'int parameter(int x) { return x+2; }').replace('Box box =', 'var box =').replace('int[] values =', 'owned int[] values =').replace('values[tick(0)] += tick(2);', 'int index = tick(0); int previous = values[index]; int addend = tick(2); values[index] = previous + addend;')
		cases.append(('compound-places', COMPOUND_PLACE, legacy_places))
	products = {str(bridge_object):sha(bridge_object)}
	for name, modern, legacy in cases:
		source = runtime/(name+'.astra')
		oracle_source = runtime/(name+'-legacy.astra')
		source.write_text('language astra27b;\n'+modern)
		oracle_source.write_text(legacy)
		identity = {str(path):sha(path) for path in (source, oracle_source)}
		source_inputs.update(identity)
		write(runtime/'inputs.json', source_inputs)
		oracle = build/(name+'-C0')
		links = [arg for path in objects for arg in ('--link-object', path)]
		run(name+'-C0-build', [a.c0, '-O0', oracle_source, *links, '-o', oracle])
		run(name+'-C0-native', [oracle], 42)
		products[str(oracle)] = sha(oracle)
		for mode in ('O0', 'O2'):
			obj = build/(name+'-'+mode+'.o')
			target = build/(name+'-'+mode)
			run(name+'-'+mode+'-compile', [a.compiler, '-c', '-'+mode, '-o', obj, source])
			run(name+'-'+mode+'-link', ['cc', '-no-pie', obj, *objects, '-o', target])
			run(name+'-'+mode+'-native', [target], 42)
			memory(name+'-'+mode+'-memory', [target], 42)
			products[str(target)] = sha(target)
			products[str(obj)] = sha(obj)
		memory(name+'-compiler-memory', [a.compiler, '--emit-llvm', '-o', build/(name+'-memory.ll'), source], 0)
		products[str(build/(name+'-memory.ll'))] = sha(build/(name+'-memory.ll'))
		assert all(sha(path) == digest for path, digest in identity.items())
	negative = [('numeric-overflow', 'int main() { u8 value = 0x100; return value as int; }'), ('borrow-consume', ITEM+'int consume(owned Item item) { return item.value; } int inspect(Item item) { return consume(move item); } int main() { var item = new Item(42); return inspect(item); }'), ('double-move', ITEM+'int consume(owned Item item) { return item.value; } int main() { var item = new Item(21); return consume(move item)+consume(move item); }')]
	if 'records' in a.feature:
		negative += [('record-missing', 'struct Point { int x; int y; } int main() { var p = Point {x = 42}; return p.x; }'), ('record-duplicate', 'struct Point { int x; int y; } int main() { var p = Point {x = 42, x = 1}; return p.x; }')]
	if 'conditional' in a.feature:
		negative += [('conditional-type', 'int main() { return true ? 42 : false; }'), ('conditional-condition', 'int main() { return 1 ? 42 : 0; }')]
	if 'compound' in a.feature:
		negative += [('compound-narrowing', 'int main() { u8 x = 1; int y = 2; x += y; return x as int; }'), ('compound-float-remainder', 'int main() { f64 x = 42.0d; x %= 2.0d; return x as int; }'), ('compound-not-place', 'int value() { return 40; } int main() { value() += 2; return 42; }')]
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
	write(runtime/'result.json', dict(status='SELECTED_CURRENT_COMPILER_NATIVE_GATES_PASS', features=a.feature, compiler=dict(path=str(a.compiler), sha256=a.compiler_sha256), tools=tools, providers=providers, source_inputs=source_inputs, inputs_sha256=sha(runtime/'inputs.json'), products=products, commands_sha256=sha(runtime/'commands.json'), scope='Selected feature programs and source refusals only. Remaining ownership/syntax, physical mutations, full preservation and delivery gates are separate.'))
	print('SELECTED_CURRENT_COMPILER_NATIVE_GATES_PASS', flush=True)


if __name__ == '__main__':
	main()
