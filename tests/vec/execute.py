# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Vector native qualification using Astra's existing scalar authorities per lane."""
from pathlib import Path
import importlib.util
import json
import random
import re
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/f32'))
spec = importlib.util.spec_from_file_location('astra_scalar_f32_execution', ROOT / 'tests/f32/execute.py')
f32 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f32)
FIXTURES = ['basic', 'integers', 'f32', 'masks', 'branch', 'loop', 'native-call', 'order', 'ownership', 'physical']


def bindings():
	return f32.bindings()


def run(argv):
	result = subprocess.run([str(arg) for arg in argv], cwd=ROOT, capture_output=True, text=True)
	assert result.returncode == 0 and result.stdout == '' and result.stderr == '', (argv, result)


def initializer(lanes):
	return '{' + ', '.join(lanes) + '}'


def float_matrix():
	operations = [('+', lambda a, b: a + b), ('-', lambda a, b: a - b), ('*', lambda a, b: a * b), ('/', lambda a, b: a / b)]
	predicates = [('==', lambda a, b: a == b), ('!=', lambda a, b: a != b), ('<', lambda a, b: a < b), ('<=', lambda a, b: a <= b), ('>', lambda a, b: a > b), ('>=', lambda a, b: a >= b)]
	selected = [1, 2, 0x7fffff, 0x800000, 0x3f000000, 0x3f800000, 0x3f800001, 0x4b800000, 0x7f7fffff]
	pairs = [(a, b) for a in selected for b in selected]
	pairs += [(a | 0x80000000, b) for a, b in pairs]
	rng = random.Random(0xAEC1)
	pairs += [(rng.randrange(1, 0x7f800000) | (rng.randrange(2) << 31), rng.randrange(1, 0x7f800000) | (rng.randrange(2) << 31)) for _ in range(158)]
	lines, calls = [], []
	checks = 0
	for lanes in [2, 4]:
		type_name = f'f32<{lanes}>'
		for op, (operator, _) in enumerate(operations + predicates):
			result = type_name if op < 4 else f'bool<{lanes}>'
			lines.append(f'{result} op{lanes}_{op}({type_name} a,{type_name} b){{return a{operator}b;}}')
		for start in range(0, len(pairs), lanes):
			group = pairs[start:start + lanes]
			name = f'check{lanes}_{start}'
			calls.append(name)
			lines += [f'bool {name}(){{', f'\t{type_name} a={initializer([f32.literal(a) for a, _ in group])};', f'\t{type_name} b={initializer([f32.literal(b) for _, b in group])};']
			for op, (_, operation) in enumerate(operations):
				# Reuse the accepted exact scalar binary32 quantizer. There is
				# no host float or independently defined vector rounding rule.
				exact = [operation(f32.signed_value(a), f32.signed_value(b)) for a, b in group]
				bits = [f32.round_binary32(abs(x)) | (0x80000000 if x < 0 else 0) for x in exact]
				lines += [f'\t{type_name} e{op}={initializer([f32.literal(x) for x in bits])};', f'\t{type_name} r{op}=op{lanes}_{op}(a,b);', f'\tif(!all(r{op}==e{op})){{return false;}}']
				checks += lanes
				if any(x & 0x7fffffff == 0 for x in bits):
					# Reciprocals observe the exact zero sign lane-wise.
					# Expected nonzero reciprocals also use the scalar quantizer.
					reciprocals = []
					for x in bits:
						if x & 0x7fffffff == 0:
							reciprocals.append(0xff800000 if x >> 31 else 0x7f800000)
						elif x & 0x7fffffff == 0x7f800000:
							reciprocals.append(x & 0x80000000)
						else:
							v = 1 / f32.signed_value(x)
							reciprocals.append(f32.round_binary32(abs(v)) | (0x80000000 if v < 0 else 0))
					lines += [f'\t{type_name} one{op}={initializer(["1.0"] * lanes)};', f'\t{type_name} reciprocal{op}={initializer([f32.literal(x) for x in reciprocals])};', f'\tif(!all(op{lanes}_3(one{op},r{op})==reciprocal{op})){{return false;}}']
					checks += lanes
			for op, (_, predicate) in enumerate(predicates, 4):
				expected = [str(predicate(f32.signed_value(a), f32.signed_value(b))).lower() for a, b in group]
				lines += [f'\tbool<{lanes}> e{op}={initializer(expected)};', f'\tif(!all(op{lanes}_{op}(a,b)==e{op})){{return false;}}']
				checks += lanes
			lines += ['\treturn true;', '}']
	lines += ['int main(){'] + [f'\tif(!{name}()){{return 1;}}' for name in calls] + ['\treturn 0;', '}']
	return '\n'.join(lines) + '\n', {'scalar_pairs_per_shape': len(pairs), 'vector_cases': len(calls), 'lane_checks': checks, 'shapes': 2}


def mask_matrix():
	lines, calls = [], []
	for lanes in [2, 4, 8, 16]:
		type_name = f'bool<{lanes}>'
		lines += [f'{type_name} flip{lanes}({type_name} a){{return !a;}}', f'bool every{lanes}({type_name} a){{return all(a);}}', f'bool some{lanes}({type_name} a){{return any(a);}}']
		patterns = [[True] * lanes, [False] * lanes, [i % 2 == 0 for i in range(lanes)]]
		patterns += [[i == k for i in range(lanes)] for k in range(lanes)]
		patterns += [[i != k for i in range(lanes)] for k in range(lanes)]
		for trial, mask in enumerate(patterns):
			name = f'mask{lanes}_{trial}'
			calls.append(name)
			lines += [f'bool {name}(){{', f'\t{type_name} a={initializer([str(x).lower() for x in mask])};', f'\t{type_name} b={initializer([str(not x).lower() for x in mask])};', f'\treturn all(flip{lanes}(a)==b) && every{lanes}(a)=={str(all(mask)).lower()} && some{lanes}(a)=={str(any(mask)).lower()};', '}']
	lines += ['int main(){'] + [f'\tif(!{name}()){{return 1;}}' for name in calls] + ['\treturn 0;', '}']
	return '\n'.join(lines) + '\n', len(calls)


def main(compiler, companion, oracle, out):
	out.mkdir(parents=True, exist_ok=True)
	rows = []
	for name in FIXTURES:
		source = ROOT / f'tests/vec/fixtures/vec-{name}.astra'
		options = [*bindings(), '--link-object', companion] if name == 'ownership' else []
		run([compiler, source, *options, '-o', out / name])
		run([out / name])
		rows.append({'fixture': name, 'passed': True})
	result = subprocess.run([str(oracle)], capture_output=True, text=True, check=True)
	assert result.stderr == ''
	integer_text = result.stdout
	match = re.search(r'oracle shapes=(\d+) vectors=(\d+) lane_checks=(\d+)', integer_text)
	assert match
	integer_counts = dict(zip(['shapes', 'vectors', 'lane_checks'], map(int, match.groups())))
	float_text, float_counts = float_matrix()
	mask_text, mask_cases = mask_matrix()
	for name, text in [('integer-oracle', integer_text), ('f32-oracle', float_text), ('mask-matrix', mask_text)]:
		source = out / (name + '.astra')
		source.write_text(text)
		run([compiler, source, '-o', out / name])
		run([out / name])
	rows += [{'integer_oracle': integer_counts}, {'f32_oracle': float_counts}, {'mask_cases': mask_cases}]
	# Lane-zero trap must precede a later lane's side effect. abort() produces
	# SIGABRT, whereas Astra integer division by zero produces SIGILL here.
	source = out / 'trap-order.astra'
	source.write_text('extern(C) void abort(); int effect(){abort();return 1;} int main(){int z=0;int<2> v={1/z,effect()};return 0;}\n')
	run([compiler, source, '-o', out / 'trap-order'])
	result = subprocess.run([str(out / 'trap-order')], capture_output=True)
	assert result.returncode == -4 and result.stdout == result.stderr == b'', result
	rows.append({'lane_trap_before_later_effect': 'SIGILL'})
	source = out / 'bad-entry.astra'
	source.write_text('int<2> main(){int<2> v={0,0};return v;}\n')
	result = subprocess.run([str(compiler), str(source), '-o', str(out / 'bad-entry')], capture_output=True, text=True)
	assert result.returncode == 1 and 'main must return int' in result.stderr and not (out / 'bad-entry').exists()
	(out / 'results.json').write_text(json.dumps(rows, indent='\t') + '\n')
	print(json.dumps({'runtime_fixtures': len(FIXTURES), 'integer_oracle': integer_counts, 'f32_oracle': float_counts, 'mask_cases': mask_cases, 'trap_order': True, 'vector_main_rejected': True}), flush=True)


if __name__ == '__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
