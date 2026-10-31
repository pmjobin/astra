# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real source consumers, rational numerical oracles, fatal contracts and source identity."""
from pathlib import Path
import itertools
import json
import os
import re
import resource
import subprocess
import sys

sys.dont_write_bytecode = True
from oracle import Format, integer_cases

ROOT = Path(__file__).resolve().parents[2]
LIB = ROOT / 'lib/astra'
FIX = ROOT / 'tests/baselib/fixtures'
BASE = [LIB / ('base/' + name + '.astra') for name in ['order', 'classify', 'contracts', 'clamp']]
EQUALITY = LIB / 'hosted/equality.astra'
MATH = LIB / 'hosted/math.vapi'
STAGES = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
MODES = ['O0', 'O2', 'fma', 'preserved']
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def process(argv, cwd=ROOT):
	return subprocess.run(list(map(str, argv)), cwd=cwd, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))


def run(argv, output=None, cwd=ROOT):
	p = process(argv, cwd)
	assert p.returncode == 0 and not p.stderr and (output is None or p.stdout == output), (argv, p.returncode, p.stdout, p.stderr, output)
	return p.stdout


def write_json(path, value):
	path.write_text(json.dumps(value, indent='\t') + '\n')


def matrix(out):
	integers = integer_cases()
	header = ['#include <stdint.h>', '#define INTEGER_COUNT ' + str(len(integers['int'])), 'static const int32_t integer_cases[6][INTEGER_COUNT][4] = {']
	for cases in integers.values():
		header.append('{\n' + ',\n'.join('{' + ','.join(map(str, row)) + '}' for row in cases) + '\n},')
	header.append('};')
	records = {'integers': {name: len(rows) for name, rows in integers.items()}, 'floating': {}}
	for width in [32, 64]:
		fmt = Format(width)
		patterns = fmt.patterns()
		# Quiet-NaN operand transport is qualified. Signaling NaNs are classified only.
		selections = [b for b in patterns if fmt.category(b) != 3 or b & fmt.quiet]
		pairs = [[a, b, fmt.select(a, b), fmt.select(a, b, True)] for a in selections for b in selections]
		bounds = [(fmt.sign | fmt.inf, fmt.inf), (fmt.sign | fmt.maximum, fmt.maximum), (fmt.sign, 0), (0, fmt.sign), (0, 0), (1 << fmt.fraction, fmt.maximum)]
		clamps = [[v, lo, hi, lo if fmt.less(v, lo) else hi if fmt.less(hi, v) else v] for v in selections for lo, hi in bounds]
		math = [[fmt.math(op, b) for op in ['sqrt', 'floor', 'ceil', 'trunc', 'abs']] for b in patterns]
		def array(name, rows, columns=None):
			literal = lambda b: f'UINT{width}_C(0x{b:0{width // 4}x})'
			body = ',\n'.join('{' + ','.join(literal(b) for b in row) + '}' for row in rows) if columns else ',\n'.join(literal(b) for b in rows)
			header.append(f'static const uint{width}_t {name}{width}[]' + (f'[{columns}]' if columns else '') + ' = {\n' + body + '\n};')
		array('inputs', patterns)
		array('pairs', pairs, 4)
		array('clamps', clamps, 4)
		array('math_bits', [[b if b is not None else 0 for b in row] for row in math], 5)
		header.append(f'static const int categories{width}[] = {{' + ','.join(str(fmt.category(b)) for b in patterns) + '};')
		header.append(f'static const int math_nan{width}[][5] = {{' + ','.join('{' + ','.join('1' if b is None else '0' for b in row) + '}' for row in math) + '};')
		records['floating'][str(width)] = dict(patterns=[f'{b:0{width // 4}x}' for b in patterns], categories=[fmt.category(b) for b in patterns], pairs=len(pairs), clamps=len(clamps), math=len(math) * 5, maximum=f'{fmt.maximum:x}', exact_limit_integer=str(fmt.rational(fmt.maximum).numerator))
	(out / 'matrix.h').write_text('\n'.join(header) + '\n')
	write_json(out / 'matrix.json', records)
	return records


def numerical_source(out):
	lines = ['extern(C) int test_integer(int type, int row, int column);', 'extern(C) int test_integer_count();', 'extern(C) int test_environment();']
	for index, name in enumerate(integer_cases()):
		lines += [f'void check_{name}() {{', '\tint row = 0;', '\twhile (row < test_integer_count()) {', f'\t\tvar a = test_integer({index}, row, 0) as {name};', f'\t\tvar b = test_integer({index}, row, 1) as {name};', f'\t\tvar lo = test_integer({index}, row, 2) as {name};', f'\t\tvar hi = test_integer({index}, row, 3) as {name};', '\t\tassert_code(min(a, b) == lo, row);', '\t\tassert_code(max(a, b) == hi, row);', '\t\tassert_code(clamp(a, lo, hi) == a, row);', '\t\tassert_code(clamp(b, lo, hi) == b, row);', '\t\tassert_code(clamp(a, b, b) == b, row);', '\t\trow = row + 1;', '\t}', '}']
	for w in [32, 64]:
		for declaration in [f'f{w} test_input{w}(int row)', f'int test_count{w}()', f'int test_category{w}(int row)', f'int test_pair_count{w}()', f'f{w} test_pair_input{w}(int row, int column)', f'int test_pair_check{w}(int row, int column, f{w} value)', f'int test_clamp_count{w}()', f'f{w} test_clamp_input{w}(int row, int column)', f'int test_clamp_check{w}(int row, f{w} value)']:
			lines.append('extern(C) ' + declaration + ';')
		lines += [f'void check_f{w}() {{', '\tint row = 0;', f'\twhile (row < test_count{w}()) {{', f'\t\tvar value = test_input{w}(row);', f'\t\tvar category = test_category{w}(row);', f'\t\tassert_code(is_nan_f{w}(value) == (category == 3), row);', f'\t\tassert_code(is_finite_f{w}(value) == (category == 1), row);', f'\t\tassert_code(is_infinite_f{w}(value) == (category == 2), row);', '\t\trow = row + 1;', '\t}', '\trow = 0;', f'\twhile (row < test_pair_count{w}()) {{', f'\t\tvar a = test_pair_input{w}(row, 0);', f'\t\tvar b = test_pair_input{w}(row, 1);', f'\t\tassert_code(test_pair_check{w}(row, 2, min(a, b)) == 0, row);', f'\t\tassert_code(test_pair_check{w}(row, 3, max(a, b)) == 0, row);', '\t\trow = row + 1;', '\t}', '\trow = 0;', f'\twhile (row < test_clamp_count{w}()) {{', f'\t\tvar value = test_clamp_input{w}(row, 0);', f'\t\tvar lower = test_clamp_input{w}(row, 1);', f'\t\tvar upper = test_clamp_input{w}(row, 2);', f'\t\tassert_code(test_clamp_check{w}(row, clamp(value, lower, upper)) == 0, row);', '\t\trow = row + 1;', '\t}', '}']
	lines += ['int main() {', '\tassert_code(test_environment() == 0, -1);', *['\tcheck_' + name + '();' for name in [*integer_cases(), 'f32', 'f64']], '\treturn 0;', '}']
	path = out / 'numerical.astra'; path.write_text('\n'.join(lines) + '\n'); return path


def math_source(out):
	lines = ['extern(C) int test_environment();']
	for w in [32, 64]:
		lines += [f'extern(C) f{w} test_input{w}(int row);', f'extern(C) int test_count{w}();', f'extern(C) int test_math_check{w}(int row, int operation, f{w} value);', f'extern(C) int test_math_provider{w}(int row, int operation, f{w} value);', f'void check_f{w}() {{', '\tint row = 0;', f'\twhile (row < test_count{w}()) {{', f'\t\tvar input = test_input{w}(row);']
		for index, op in enumerate(['sqrt', 'floor', 'ceil', 'trunc', 'abs']):
			lines += [f'\t\tvar {op}_result = {op}_f{w}(input);', f'\t\tassert_code(test_math_check{w}(row, {index}, {op}_result) == 0, row * 10 + {index});', f'\t\tassert_code(test_math_provider{w}(row, {index}, {op}_result) == 0, row * 10 + {index});']
		lines += ['\t\trow = row + 1;', '\t}', '}']
	lines += ['int main() { assert_code(test_environment() == 0, -1); check_f32(); check_f64(); return 0; }']
	path = out / 'math.astra'; path.write_text('\n'.join(lines) + '\n'); return path


class Campaign:
	def __init__(self, compiler, out):
		self.compiler, self.out = compiler, out
		self.records = dict(runs=[], dumps=[], permutations=[], negative=[], signatures=[], source_changes=[])
		self.trap = compiler.parent / 'lib/astra/failure-trap.o'
		self.hosted = compiler.parent / 'lib/astra/failure-hosted.o'
		self.companion = out / 'companion.o'
		self.records['matrix'] = matrix(out)
		run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-builtin', '-frounding-math', '-I', out, '-c', ROOT / 'tests/baselib/companion.c', '-o', self.companion])

	def dumps(self, name, sources, vapi=None, stages=STAGES):
		result = {}
		for stage in stages:
			args = [self.compiler, '--dump-' + stage, *sources] + (['--vapi', vapi] if vapi and stage != 'syntax' else [])
			data = run(args)
			assert data == run(args), (name, stage, 'process determinism')
			(self.out / (name + '.' + stage)).write_text(data)
			result[stage] = data
			self.records['dumps'].append(name + ':' + stage)
		return result

	def execute(self, name, sources, provider=None, vapi=None, companion=True, stdout='', stderr='', fatal=False, modes=MODES):
		dumps = self.dumps(name, sources, vapi, ['ssa', 'llvm'])
		main = re.search(r'\(function #(\d+) "main" -> int', dumps['ssa'])[1]
		ir = dumps['llvm'] + f'\ndefine i32 @main() {{\n\t%result = call fastcc i32 @astra.fn.{main}()\n\tret i32 %result\n}}\n'
		assert not re.search(r'\b(?:fast|nnan|ninf|nsz|reassoc|afn|contract)\b', ir), name
		for mode in modes:
			stem = self.out / (name + '-' + mode)
			text = re.sub(r'^(define internal fastcc [^\n]+) \{', r'\1 noinline {', ir, flags=re.M) if mode == 'preserved' else ir
			stem.with_suffix('.input.ll').write_text(text)
			run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', stem.with_suffix('.input.ll'), '-o', stem.with_suffix('.ll')])
			run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode == 'fma' else []), stem.with_suffix('.ll'), '-o', stem.with_suffix('.o')])
			links = ([self.companion, '-Wl,--wrap=calloc,--wrap=free', '-lm'] if companion else []) + ([provider] if provider else []) + (['-lm'] if vapi == MATH else [])
			run(['cc', stem.with_suffix('.o'), *links, '-o', stem])
			p = process([stem])
			assert (p.returncode < 0 if fatal else p.returncode == 0) and p.stdout == stdout and p.stderr == stderr, (name, mode, p.returncode, p.stdout, p.stderr, stdout, stderr)
			machine = run(['objdump', '-dr', stem.with_suffix('.o')]); stem.with_suffix('.machine').write_text(machine)
			assert not re.search(r'\bv(?:fmadd|fmsub|fnmadd|fnmsub)', machine), name
			self.records['runs'].append(dict(name=name, mode=mode, status=p.returncode, stdout=p.stdout, stderr=p.stderr, fatal=fatal))
		return dumps

	def source(self, name, text):
		path = self.out / (name + '.astra'); path.write_text(text + '\n'); return path

	def numerical(self):
		dumps = self.execute('numerical', [numerical_source(self.out), *BASE], self.trap)
		for bits in ['0x47EFFFFFE0000000', '0x7FEFFFFFFFFFFFFF']:
			assert bits in dumps['llvm'], bits
		limits = run([self.compiler, '--dump-semantics', BASE[1]])
		assert '0x7f7fffff' in limits and '0x7fefffffffffffff' in limits
		(self.out / 'classify.semantics').write_text(limits)
		dumps = self.execute('math', [math_source(self.out), BASE[2]], self.hosted, MATH)
		for w, channel, suffix in [(32, 'float', 'f'), (64, 'double', '')]:
			for name in ['sqrt', 'floor', 'ceil', 'trunc', 'fabs']:
				declaration = f'declare {channel} @{name}{suffix}({channel})'
				assert declaration in dumps['llvm'] and f'call {channel} @{name}{suffix}(' in dumps['llvm']
				self.records['signatures'].append(declaration)
		assert not re.search(r'\b(readnone|readonly|nounwind)\b', dumps['llvm'])

	def contracts(self):
		prefix = 'extern(C) int test_mark(int value); extern(C) f32 test_nan32(); extern(C) f64 test_nan64();\n'
		cases = [
			('success', 'assert(test_mark(1) == 1); assert_code(test_mark(2) == 2, -2147483648); assert(true || test_mark(3) == 3); assert(!(false && test_mark(4) == 4)); assert_code(clamp(test_mark(5), test_mark(6), test_mark(7)) == 6, 1); test_mark(8);', 'E1\nE2\nE5\nE6\nE7\nE8\n', '', False),
			('assert', 'assert(test_mark(1) == 0); test_mark(99);', 'E1\n', 'astra base: assertion failure kind=1 code=0\n', True),
			('assert-code-min', 'assert_code(test_mark(1) == 0, test_mark(-2147483648)); test_mark(99);', 'E1\nE-2147483648\n', 'astra base: assertion failure kind=1 code=-2147483648\n', True),
			('assert-code-max', 'assert_code(false, 2147483647); test_mark(99);', '', 'astra base: assertion failure kind=1 code=2147483647\n', True),
			('short-circuit', 'assert(test_mark(1) == 0 && test_mark(2) == 2); test_mark(99);', 'E1\n', 'astra base: assertion failure kind=1 code=0\n', True),
			('bound-order', 'clamp(test_mark(1), test_mark(3), test_mark(2)); test_mark(99);', 'E1\nE3\nE2\n', 'astra base: clamp bounds failure kind=2 code=0\n', True),
		]
		for name in [*integer_cases(), 'f32', 'f64']:
			cases.append(('reversed-' + name, f'clamp(1 as {name}, 2 as {name}, 0 as {name}); test_mark(99);', '', 'astra base: clamp bounds failure kind=2 code=0\n', True))
		for w in [32, 64]:
			suffix = 'f' if w == 32 else 'd'
			for position in ['lower', 'upper', 'both']:
				lo = f'test_nan{w}()' if position in ['lower', 'both'] else f'0.0{suffix}'
				hi = f'test_nan{w}()' if position in ['upper', 'both'] else f'1.0{suffix}'
				cases.append((f'nan-bound-{w}-{position}', f'clamp(0.5{suffix}, {lo}, {hi}); test_mark(99);', '', 'astra base: clamp bounds failure kind=2 code=0\n', True))
		for name, body, output, errors, fatal in cases:
			source = self.source(name, prefix + 'int main() {' + body + ' return 0; }')
			for provider in ['trap', 'hosted']:
				self.execute(name + '-' + provider, [source, BASE[2], BASE[3]], self.trap if provider == 'trap' else self.hosted, stdout=output, stderr=errors if provider == 'hosted' else '', fatal=fatal)
				# Resource, Class, field and buffer cleanup: successful assertion retains all normal cleanup.
		self.execute('lifetime', [FIX / 'lifetime.astra', BASE[2]], self.hosted, FIX / 'runtime.vapi', stdout='E7\nE90\nE1\nE2\nE8\nE-90\nE-7\n')
		fatal = self.source('lifetime-fatal', (FIX / 'lifetime.astra').read_text().replace('assert(test_mark(1) == 1)', 'assert(test_mark(1) == 0)'))
		self.execute('lifetime-fatal', [fatal, BASE[2]], self.hosted, FIX / 'runtime.vapi', stdout='E7\nE90\nE1\n', stderr='astra base: assertion failure kind=1 code=0\n', fatal=True)

	def diagnostics(self):
		prefix = 'extern(C) f32 test_nan32(); extern(C) f64 test_nan64(); extern(C) int test_mark(int value);\n'
		cases = [
			('equality-success', 'assert_equal_i32(-2147483648, -2147483648, 1); assert_equal_i32(2147483647, 2147483647, 2); assert_equal_f32(-0.0f, 0.0f, 3); assert_equal_f64(0.0d, -0.0d, 4);', ''),
			('equality-i32', 'assert_equal_i32(-2147483648, 2147483647, -701); test_mark(99);', 'astra base: equality i32 code=-701 expected=2147483647 actual=-2147483648\n'),
			('equality-f32', 'assert_equal_f32(1.25f, 1.5f, 702); test_mark(99);', 'astra base: equality f32 code=702 expected=1.5 actual=1.25 expected_bits=0x3fc00000 actual_bits=0x3fa00000\n'),
			('equality-f64', 'assert_equal_f64(1.25d, 1.5d, 703); test_mark(99);', 'astra base: equality f64 code=703 expected=1.5 actual=1.25 expected_bits=0x3ff8000000000000 actual_bits=0x3ff4000000000000\n'),
			('equality-zero32', 'assert_equal_f32(-0.0f, 1.0f, 704);', 'astra base: equality f32 code=704 expected=1 actual=-0 expected_bits=0x3f800000 actual_bits=0x80000000\n'),
			('equality-zero64', 'assert_equal_f64(-0.0d, 1.0d, 705);', 'astra base: equality f64 code=705 expected=1 actual=-0 expected_bits=0x3ff0000000000000 actual_bits=0x8000000000000000\n'),
			('equality-nan32', 'assert_equal_f32(test_nan32(), test_nan32(), 706);', 'astra base: equality f32 code=706 expected=-nan actual=-nan expected_bits=0xffc0005b actual_bits=0xffc0005b\n'),
			('equality-nan64', 'assert_equal_f64(test_nan64(), test_nan64(), 707);', 'astra base: equality f64 code=707 expected=-nan actual=-nan expected_bits=0xfff800000000005b actual_bits=0xfff800000000005b\n'),
		]
		for name, body, error in cases:
			source = self.source(name, prefix + 'int main() {' + body + ' return 0; }')
			self.execute(name, [source, EQUALITY], self.hosted, stderr=error, fatal=bool(error))
			# A failed stderr stream must still terminate. No assumption about signal identity.
		with open('/dev/full', 'w') as full:
			p = subprocess.run([self.out / 'equality-f64-O0'], stdout=subprocess.PIPE, stderr=full)
			assert p.returncode < 0 and p.stdout == b''

	def identity(self):
		sources = [BASE[0], BASE[2], BASE[3], FIX / 'permutation.astra']
		dumps = self.dumps('permutation', sources)
		for order in itertools.permutations(sources):
			for stage, data in dumps.items():
				assert run([self.compiler, '--dump-' + stage, *order]) == data, (order, stage)
			self.records['permutations'].append([p.name for p in order])
		instances = dumps['instances']
		assert len(re.findall(r'\(origin #\d+ "clamp"\) \(type-arguments f64\) \(requests 2\)', instances)) == 1
		assert len(re.findall(r'\(origin #\d+ "min"\) \(type-arguments int\) \(requests 2\)', instances)) == 1
		moved = self.out / 'relocated'; moved.mkdir(exist_ok=True)
		for path in sources:
			(moved / path.name).write_bytes(path.read_bytes())
		for stage in STAGES[1:]:
			assert run([self.compiler, '--dump-' + stage, *sorted(moved.glob('*.astra'))]) == dumps[stage]
			# Exact explicit and inferred requests share every post-syntax stage.
		inferred = self.source('inferred', 'T outer<T>(T a,T b) where T : Ordered { return min(a,b); } int main(){assert(outer(2,1)==1); assert(max(2.0d,1.0d)==2.0d); assert(clamp(0.5d,0.0d,1.0d)==0.5d); return 0;}')
		explicit = self.source('explicit', inferred.read_text().replace('return min(', 'return min<T>(').replace('assert(outer(', 'assert(outer<int>(').replace('assert(max(', 'assert(max<f64>(').replace('assert(clamp(', 'assert(clamp<f64>('))
		for stage in STAGES[1:]:
			assert run([self.compiler, '--dump-' + stage, inferred, *BASE]) == run([self.compiler, '--dump-' + stage, explicit, *BASE])
			# No source-name override: an unrelated user min/assert is ordinary code.
		custom = self.source('custom', 'int min(int a,int b){return a+b;} int assert(int value){return value;} int main(){return assert(min(0,0));}')
		self.execute('custom', [custom], companion=False)
		conflict = process([self.compiler, '--check', custom, BASE[0]])
		assert conflict.returncode == 1 and 'duplicate' in conflict.stderr
		conflict = process([self.compiler, '--check', custom, BASE[2]])
		assert conflict.returncode == 1 and 'duplicate' in conflict.stderr
		mutated = self.source('changed-order', BASE[0].read_text().replace('if (b < a)', 'if (a < b)'))
		client = self.source('changed-client', 'int main(){return min(1,2)-2;}')
		self.execute('changed-order', [mutated, client], companion=False)
		self.records['source_changes'] = ['custom-min-assert', 'duplicate-min', 'duplicate-assert', 'changed-order-body']

	def negatives(self):
		types = ['bool', 'void*'] + [f'{t}<{n}>' for t, lanes in [('i8', [2, 4, 8, 16]), ('u8', [2, 4, 8, 16]), ('i16', [2, 4, 8]), ('u16', [2, 4, 8]), ('int', [2, 4]), ('u32', [2, 4]), ('f32', [2, 4]), ('bool', [2, 4, 8, 16])] for n in lanes]
		# The exact accepted universe is checked by the Vala capability authority test too.
		cases = {name: f'void use({name} x){{min(x,x);}}' for name in types}
		cases.update({'aggregate': 'struct Pair{int x;} void use(Pair x){min(x,x);}', 'typed-pointer': 'void use(int* x){min(x,x);}', 'slice': 'void use(int[] x){min(x,x);}', 'class': 'class Item{int x;init(){this.x=0;}} void use(Item x){min(x,x);}', 'outer-no-capability': 'T outer<T>(T a,T b){return min(a,b);}', 'outer-eq-only': 'T outer<T>(T a,T b) where T : Eq {return min(a,b);}', 'literal-conflict': 'void use(f64 value){clamp(value,0.0,1.0);}', 'inline-owner': 'class Item{int x;init(){this.x=0;}} owned T relay<T>(owned T x) where T : Ownable{return move x;} void use(){var x=relay(Item.init());}'})
		for name, source in cases.items():
			path = self.source('negative-' + name.replace('*', 'ptr').replace('<', '-').replace('>', '').replace('[]', 'slice'), source)
			for stage in ['semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
				p = process([self.compiler, '--dump-' + stage, path, *BASE])
				assert p.returncode == 1 and p.stdout == '' and 'error:' in p.stderr, (name, stage, p)
				if name in types:
					assert "does not satisfy capability 'Ordered'" in p.stderr, (name, p.stderr)
				(self.out / (path.stem + '.' + stage + '.stderr')).write_text(p.stderr)
				self.records['negative'].append(name + ':' + stage)


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	campaign = Campaign(compiler, out)
	campaign.numerical()
	campaign.contracts()
	campaign.diagnostics()
	campaign.identity()
	campaign.negatives()
	write_json(out / 'results.json', campaign.records)
	print(f"{len(campaign.records['runs'])} runtime executions; {len(campaign.records['permutations'])} source permutations; {len(campaign.records['negative'])} negative stage checks")


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
