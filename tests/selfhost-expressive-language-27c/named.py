#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual named-call native targets and separately authored C0 expansions."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0, str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute, output_path, sha, tool_identity, write

TICKS = '''extern(C) int tick(int value);
extern(C) int trace();
extern(C) void reset_trace();
'''
CHOOSE = 'int choose(int first, int middle, int last) { return first*100+middle*10+last; }\n'
PAIR = '''class Pair {
	int first;
	int last;
	init(int first, int last) { this.first = first; this.last = last; }
	int combine(int first, int last) { return first+last+this.first+this.last+33; }
}
'''
ITEM = '''extern(C) void note_drop(int value);
extern(C) int drops();
extern(C) int drop_sum();
class Item {
	int value;
	init(int value) { this.value = value; }
	deinit() { note_drop(this.value); }
}
'''
OWNER = TICKS+ITEM+'''int mark(bool fail) throws Error {
	int ignored = tick(7);
	if (fail) { throw new Error("named operand failure"); }
	return 0;
}
int eat(owned Item left, owned Item right, int marker) {
	return left.value+right.value+marker;
}
int attempt(bool fail) {
	var left = new Item(20);
	var right = new Item(22);
	try {
		@CALL@
	} catch (Error error) { return 42; }
}
int main() {
	reset_trace();
	if (attempt(false) != 42 || trace() != 7 || drops() != 2 || drop_sum() != 42) return 1;
	reset_trace();
	if (attempt(true) != 42 || trace() != 7 || drops() != 4 || drop_sum() != 84) return 2;
	return 42;
}
'''
THROW = TICKS+CHOOSE+'''int risky() throws Error { int ignored = tick(2); throw new Error("operand stop"); }
int main() {
	reset_trace();
	try { @CALL@ }
	catch (Error error) { if (trace() == 12) return 42; }
	return 1;
}
'''
CASES = [
	('scalar-order', TICKS+CHOOSE+'''int main() {
	reset_trace();
	if (choose(last: tick(3), first: tick(1), middle: tick(2)) != 123 || trace() != 312) return 1;
	reset_trace();
	if (choose(tick(1), last: tick(3), middle: tick(2)) != 123 || trace() != 132) return 2;
	return 42;
}
''', TICKS+CHOOSE+'''int main() {
	reset_trace();
	int last = tick(3); int first = tick(1); int middle = tick(2);
	if (choose(first, middle, last) != 123 || trace() != 312) return 1;
	reset_trace();
	int other_first = tick(1); int other_last = tick(3); int other_middle = tick(2);
	if (choose(other_first, other_middle, other_last) != 123 || trace() != 132) return 2;
	return 42;
}
''', False),
	('typed-labels', '''int typed(bool enabled, u8 small, f64 wide) {
	if (enabled && small == 2 && wide == 40.0d) return 42;
	return 1;
}
int main() { return typed(wide: 40.0d, small: 2, enabled: true); }
''', '''int typed(bool enabled, u8 small, f64 wide) {
	if (enabled && small == 2 && wide == 40.0d) return 42;
	return 1;
}
int main() { return typed(true, 2, 40.0d); }
''', False),
	('generic-labels', '''T choose_value<T>(bool enabled, T value) { if (enabled) return value; return value; }
int main() {
	if (choose_value(value: 42, enabled: true) != 42) return 1;
	return choose_value<int>(value: 42, enabled: false);
}
''', '''T choose_value<T>(bool enabled, T value) { if (enabled) return value; return value; }
int main() {
	if (choose_value(true, 42) != 42) return 1;
	return choose_value<int>(false, 42);
}
''', False),
	('constructor-method-order', TICKS+PAIR+'''int main() {
	reset_trace();
	var pair = new Pair(last: tick(2), first: tick(4));
	if (trace() != 24 || pair.first != 4 || pair.last != 2) return 1;
	reset_trace();
	int result = pair.combine(last: tick(2), first: tick(1));
	if (trace() != 21) return 2;
	return result;
}
''', TICKS+PAIR+'''int main() {
	reset_trace();
	int last = tick(2); int first = tick(4);
	var pair = new Pair(first, last);
	if (trace() != 24 || pair.first != 4 || pair.last != 2) return 1;
	reset_trace();
	int call_last = tick(2); int call_first = tick(1);
	int result = pair.combine(call_first, call_last);
	if (trace() != 21) return 2;
	return result;
}
''', False),
	('C-ABI-order', TICKS+'''extern(C) int c_sum(int first, int last);
int main() {
	reset_trace();
	int result = c_sum(last: tick(2), first: tick(4));
	if (trace() != 24 || result != 6) return 1;
	return result+36;
}
''', TICKS+'''extern(C) int c_sum(int first, int last);
int main() {
	reset_trace();
	int last = tick(2); int first = tick(4);
	int result = c_sum(first, last);
	if (trace() != 24 || result != 6) return 1;
	return result+36;
}
''', False),
	('owned-call-abort', OWNER.replace('@CALL@', 'return eat(right: move right, left: move left, marker: mark(fail));'), OWNER.replace('@CALL@', 'int marker = mark(fail); return eat(move left, move right, marker);'), True),
	('owner-reservation-written-order', OWNER.replace('int eat(owned Item left, owned Item right, int marker)', 'int eat(int marker, owned Item left, owned Item right)').replace('@CALL@', 'return eat(right: move right, marker: mark(fail), left: move left);'), OWNER.replace('int eat(owned Item left, owned Item right, int marker)', 'int eat(int marker, owned Item left, owned Item right)').replace('@CALL@', 'int marker = mark(fail); return eat(marker, move left, move right);'), True),
	('caller-expression-label', '''bool observe(int first, int last, [CallerArgumentExpression("first")] string expression) {
	return first == 20 && last == 22 && expression == "10 * 2";
}
int main() { if (observe(last: 22, first: 10 * 2)) return 42; return 1; }
''', '''bool observe(int first, int last, [CallerArgumentExpression("first")] string expression) {
	return first == 20 && last == 22 && expression == "10 * 2";
}
int main() { if (observe(10 * 2, 22)) return 42; return 1; }
''', False),
	('throw-order', THROW.replace('@CALL@', 'int value = choose(first: tick(1), middle: risky(), last: tick(3));'), THROW.replace('@CALL@', 'int first = tick(1); int middle = risky(); int last = tick(3); int value = choose(first, middle, last);'), True),
	('namespace-call', '''int main() { return Helpers.add(last: 22, first: 20); }
''', '''int main() { return Helpers.add(20, 22); }
''', False),
]
NEGATIVE = [
	('duplicate', CHOOSE+'int main() { return choose(first: 1, first: 2, last: 3); }'),
	('missing', CHOOSE+'int main() { return choose(first: 1, last: 3); }'),
	('unknown', CHOOSE+'int main() { return choose(first: 1, middle: 2, missing: 3); }'),
	('positional-tail', CHOOSE+'int main() { return choose(first: 1, 2, 3); }'),
	('positional-label-collision', CHOOSE+'int main() { return choose(1, first: 2, last: 3); }'),
	('wrong-type', CHOOSE+'int main() { return choose(first: true, middle: 2, last: 3); }'),
	('intrinsic-label', 'int main() { int[1] data = {42}; return len(value: data); }'),
	('double-owner', ITEM+'int take(owned Item first, owned Item last) { return first.value+last.value; } int main() { var item = new Item(21); return take(last: move item, first: move item); }'),
	('borrowed-consume', ITEM+'int take(owned Item value) { return value.value; } int inspect(Item value) { return take(value: move value); } int main() { var item = new Item(42); return inspect(item); }'),
	('hidden-receiver-label', PAIR+'int main() { var pair = new Pair(4, 2); return pair.combine(_astra_receiver: pair, first: 1, last: 2); }'),
]

MATCH_TAG = 'enum Mode { First, Middle, Last }\n'
MATCH_CASES = [
	('match-three-way', MATCH_TAG+'''int status(Mode value) => match (value) {
	case Mode.Last() => 42;
	case Mode.First() => 20;
	case Mode.Middle() => 22;
};
int main() { if (status(Mode.First()) != 20 || status(Mode.Middle()) != 22) return 1; return status(Mode.Last()); }
''', MATCH_TAG+'''int status(Mode value) {
	match (value) {
		case Mode.Last(): { return 42; }
		case Mode.First(): { return 20; }
		case Mode.Middle(): { return 22; }
	}
}
int main() { if (status(Mode.First()) != 20 || status(Mode.Middle()) != 22) return 1; return status(Mode.Last()); }
''', False),
	('match-single-scrutinee', TICKS+MATCH_TAG+'''Mode input() { int ignored = tick(1); return Mode.Middle(); }
int main() {
	reset_trace();
	int result = match (input()) {
		case Mode.First() => tick(3);
		case Mode.Middle() => tick(2)+40;
		case Mode.Last() => tick(4);
	};
	if (trace() != 12) return 1;
	return result;
}
''', TICKS+MATCH_TAG+'''Mode input() { int ignored = tick(1); return Mode.Middle(); }
int main() {
	reset_trace();
	int result = 0;
	match (input()) {
		case Mode.First(): { result = tick(3); }
		case Mode.Middle(): { result = tick(2)+40; }
		case Mode.Last(): { result = tick(4); }
	}
	if (trace() != 12) return 1;
	return result;
}
''', False),
	('match-owned-result', ITEM+MATCH_TAG+'''owned Item make(Mode value) {
	return match (value) {
		case Mode.First() => new Item(20);
		case Mode.Middle() => new Item(22);
		case Mode.Last() => new Item(42);
	};
}
int run() { var item = make(Mode.Last()); return item.value; }
int main() { if (run() != 42 || drops() != 1 || drop_sum() != 42) return 1; return 42; }
''', ITEM+MATCH_TAG+'''owned Item make(Mode value) {
	match (value) {
		case Mode.First(): { var item = new Item(20); return move item; }
		case Mode.Middle(): { var item = new Item(22); return move item; }
		case Mode.Last(): { var item = new Item(42); return move item; }
	}
}
int run() { var item = make(Mode.Last()); return item.value; }
int main() { if (run() != 42 || drops() != 1 || drop_sum() != 42) return 1; return 42; }
''', False),
]
MATCH_NEGATIVE = [
	('match-nonexhaustive', MATCH_TAG+'int main() { return match (Mode.First()) { case Mode.First() => 42; case Mode.Last() => 3; }; }'),
	('match-overlap', MATCH_TAG+'int main() { return match (Mode.First()) { case Mode.First() => 42; case Mode.First() => 3; case Mode.Last() => 4; }; }'),
	('match-result-type', MATCH_TAG+'int main() { return match (Mode.First()) { case Mode.First() => 42; case Mode.Middle() => true; case Mode.Last() => 3; }; }'),
	('match-foreign-variant', MATCH_TAG+'enum Other { First } int main() { return match (Mode.First()) { case Other.First() => 42; case Mode.Middle() => 2; case Mode.Last() => 3; }; }'),
	('match-borrow-escape', ITEM+MATCH_TAG+'Item choose(Mode value, Item item) { return match (value) { case Mode.First() => item; case Mode.Middle() => item; case Mode.Last() => item; }; } int main() { return 42; }'),
]


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for n in ('compiler', 'c0', 'link', 'build', 'runtime'): p.add_argument('--'+n, type=Path, required=True)
	p.add_argument('--compiler-sha256', required=True); p.add_argument('--c0-sha256', required=True)
	p.add_argument('--oracle-only', action='store_true'); p.add_argument('--case', action='append')
	p.add_argument('--feature', choices=('named', 'match'), default='named')
	a = p.parse_args()
	assert sha(a.compiler) == a.compiler_sha256 and sha(a.c0) == a.c0_sha256
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	build = output_path(a.build, WORK/'build'); build.mkdir(parents=True, exist_ok=False)
	runtime = output_path(a.runtime, WORK/'runtime'); runtime.mkdir(parents=True, exist_ok=False)
	providers = {n:h for n,h in json.loads(a.link.read_text())['objects'].items() if Path(n).name not in ('llvm-capi.o', 'arguments.o')}
	assert len(providers) == 5 and all(sha(n) == h for n,h in providers.items())
	tools = tool_identity([a.compiler, a.c0, sys.executable, *[shutil.which(n) for n in ('gcc', 'cc', 'opt', 'readelf', 'valgrind', 'llvm-config')]])
	env = dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'); env.pop('LD_PRELOAD', None); env.pop('VALGRIND_OPTS', None)
	inputs = {str(Path(__file__)):sha(__file__), str(a.link):sha(a.link)}; products = {}; commands = []
	def run(name, argv, expected=0):
		r = execute(argv, runtime/name, expected=expected, timeout=900, env=env)
		commands.append(dict(name=name, argv=list(map(str, argv)), result=r)); write(runtime/'commands.json', commands)
		print(name, r['status'], round(r['seconds'], 3), flush=True)
		assert r['status'] == 'EXPECTED_OUTCOME', (name, r)
	def memory(name, argv, expected):
		run(name, ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *argv], expected)
		log = (runtime/name/'stderr').read_bytes()
		assert all(m in log for m in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
	bridge = runtime/'observe.c'
	bridge.write_text('static int seen, retired, sum;\nint tick(int v) { seen = seen*10+v; return v; }\nint trace(void) { return seen; }\nvoid reset_trace(void) { seen = 0; }\nvoid note_drop(int v) { ++retired; sum += v; }\nint drops(void) { return retired; }\nint drop_sum(void) { return sum; }\nint c_sum(int first, int last) { return first+last; }\n')
	inputs[str(bridge)] = sha(bridge); bridge_object = build/'observe.o'
	run('C-observer', ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', bridge, '-o', bridge_object])
	objects = [*providers, str(bridge_object)]
	cases = [r for r in CASES if not a.case or r[0] in a.case]
	negatives = NEGATIVE
	if a.feature == 'match':
		cases = [r for r in MATCH_CASES if not a.case or r[0] in a.case]
		negatives = MATCH_NEGATIVE
	assert cases and (not a.case or set(a.case) == {r[0] for r in cases})
	for name, modern, expanded, errors in cases:
		source = runtime/(name+'.astra'); source.write_text('language astra27b;\n'+modern)
		oracle = runtime/(name+'-expanded.astra'); oracle.write_text(expanded)
		extra = [ROOT/'lib/astra/base/errors.astra', ROOT/'lib/astra/hosted/text.astra'] if errors else []
		if name == 'namespace-call':
			helper = runtime/'Helpers.astra'; helper.write_text('namespace Helpers;\nint add(int first, int last) { return first+last; }\n')
			extra.append(helper)
		inputs.update({str(n):sha(n) for n in [source, oracle, *extra]}); write(runtime/'inputs.json', inputs)
		reference = build/(name+'-C0'); links = [arg for n in objects for arg in ('--link-object', n)]
		run(name+'-C0-compile', [a.c0, '-O0', oracle, *extra, *links, '-o', reference])
		run(name+'-C0-native', [reference], 42); products[str(reference)] = sha(reference)
		if a.oracle_only: continue
		for mode in ('O0', 'O2'):
			obj = build/(name+'-'+mode+'.o'); target = build/(name+'-'+mode)
			run(name+'-'+mode+'-compile', [a.compiler, '-c', '-'+mode, '-o', obj, source, *extra])
			run(name+'-'+mode+'-link', ['cc', '-no-pie', obj, *objects, '-o', target])
			elf = subprocess.check_output(['readelf', '-h', target], text=True)
			assert 'ELF64' in elf and 'Advanced Micro Devices X86-64' in elf
			run(name+'-'+mode+'-native', [target], 42); memory(name+'-'+mode+'-memory', [target], 42)
			products[str(target)] = sha(target); products[str(obj)] = sha(obj)
		ir = build/(name+'.ll')
		memory(name+'-compiler-memory', [a.compiler, '--emit-llvm', '-o', ir, source, *extra], 0)
		run(name+'-LLVM-verify', ['opt', '-passes=verify', '-disable-output', ir]); products[str(ir)] = sha(ir)
		write(runtime/'products.json', products)
	for name, text in [] if a.oracle_only else negatives:
		source = runtime/(name+'-negative.astra'); source.write_text('language astra27b;\n'+text+'\n')
		inputs[str(source)] = sha(source); write(runtime/'inputs.json', inputs)
		target = build/(name+'-sentinel.ll'); marker = b'ASTRA27C_NAMED_REFUSAL_SENTINEL\n'; target.write_bytes(marker)
		run(name+'-reject', [a.compiler, '--emit-llvm', '-o', target, source], 1)
		assert target.read_bytes() == marker and (runtime/(name+'-reject/stderr')).stat().st_size > 0
	assert all(sha(n) == h for n,h in {**inputs, **providers, **tools, **products}.items())
	write(runtime/'identity.json', dict(inputs=inputs, providers=providers, tools=tools, products=products, environment={n:env.get(n) for n in ('PATH', 'LD_LIBRARY_PATH', 'PYTHONHOME', 'LIBRARY_PATH', 'LC_ALL', 'LANG')}))
	write(runtime/'result.json', dict(status='EXPANDED_C0_ORACLES_ONLY' if a.oracle_only else 'SELECTED_EXPRESSIVE_NATIVE_AND_MEMORY_PASS', feature=a.feature, compiler_sha256=a.compiler_sha256, oracle_only=a.oracle_only, cases=[r[0] for r in cases], negatives=0 if a.oracle_only else len(negatives), identity_sha256=sha(runtime/'identity.json'), commands_sha256=sha(runtime/'commands.json'), limitation='Selected actual source behavior only. Independent source/owner/LLVM corruptions and full current compiler qualification remain separate gates.'))


if __name__ == '__main__': main()
