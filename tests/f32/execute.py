# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Native f32 runtime qualification; C companions only handle Resource/int."""
from pathlib import Path
import json
import random
import subprocess
import sys

sys.dont_write_bytecode = True
from oracle import round_binary32, spelling, value
from reference import BINARY32

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ['basic', 'literals', 'special', 'rounding', 'compare', 'branch', 'loop', 'struct', 'addressable', 'native-call', 'ownership', 'physical']


def bindings():
	return [arg for name in ['types', 'api'] for arg in ['--vapi', ROOT / f'tests/resource/fixtures/resource-{name}.vapi']]


def run(argv):
	result = subprocess.run([str(arg) for arg in argv], cwd=ROOT, capture_output=True, text=True)
	assert result.returncode == 0 and result.stdout == '' and result.stderr == '', (argv, result)


def literal(bits):
	magnitude = bits & 0x7fffffff
	text = '1e100' if magnitude == 0x7f800000 else spelling(value(magnitude))
	return '-' + text if bits >> 31 else text


def signed_value(bits):
	return (-1 if bits >> 31 else 1) * value(bits & 0x7fffffff)


def matrix():
	operations = [('add', '+'), ('sub', '-'), ('mul', '*'), ('div', '/')]
	predicates = [('eq', '=='), ('ne', '!='), ('lt', '<'), ('le', '<='), ('gt', '>'), ('ge', '>=')]
	lines = [f'f32 {name}(f32 a, f32 b) {{ return a {op} b; }}' for name, op in operations]
	lines += [f'bool {name}(f32 a, f32 b) {{ return a {op} b; }}' for name, op in predicates]
	selected = [1, 2, 0x7fffff, 0x800000, 0x3f000000, 0x3f800000, 0x3f800001, 0x4b800000, 0x7f7fffff]
	pairs = [(a, b) for a in selected for b in selected]
	pairs += [(a | 0x80000000, b) for a, b in pairs]
	rng = random.Random(0xF321)
	pairs += [(rng.randrange(1, 0x7f800000) | (rng.randrange(2) << 31), rng.randrange(1, 0x7f800000) | (rng.randrange(2) << 31)) for _ in range(128)]
	checks = 0
	for i, (a, b) in enumerate(pairs):
		x, y = signed_value(a), signed_value(b)
		la, lb = literal(a), literal(b)
		lines += [f'bool check{i}() {{']
		for op, symbol in operations:
			bits = BINARY32.arithmetic(symbol, a, b)
			lines.append(f'\tf32 {op}_result = {op}({la}, {lb});')
			lines.append(f'\tif ({op}_result != {literal(bits)}) {{ return false; }}')
			checks += 1
			if bits & 0x7fffffff == 0:
				lines.append(f'\tif (div(1.0, {op}_result) != {"-" if bits >> 31 else ""}1e100) {{ return false; }}')
				checks += 1
		for (op, _), expected in zip(predicates, [x == y, x != y, x < y, x <= y, x > y, x >= y]):
			lines.append(f'\tif ({op}({la}, {lb}) != {str(expected).lower()}) {{ return false; }}')
			checks += 1
		lines += ['\treturn true;', '}']
	for start in range(0, len(pairs), 16):
		lines.append(f'bool group{start}() {{ return ' + ' && '.join(f'check{i}()' for i in range(start, min(start + 16, len(pairs)))) + '; }')
	lines += ['int main() {']
	for start in range(0, len(pairs), 16):
		lines.append(f'\tif (!group{start}()) {{ return 1; }}')
	lines += ['\treturn 0;', '}']
	return '\n'.join(lines) + '\n', len(pairs), checks


def main(compiler, companion, out):
	out.mkdir(parents=True, exist_ok=True)
	rows = []
	for name in FIXTURES:
		source = ROOT / f'tests/f32/fixtures/f32-{name}.astra'
		options = [*bindings(), '--link-object', companion] if name == 'ownership' else []
		run([compiler, source, *options, '-o', out / name])
		run([out / name])
		rows.append({'fixture': name, 'passed': True})
	text, pairs, checks = matrix()
	source = out / 'matrix.astra'
	source.write_text(text)
	run([compiler, source, '-o', out / 'matrix'])
	run([out / 'matrix'])
	rows.append({'matrix_pairs': pairs, 'exact_rational_runtime_checks': checks, 'passed': True})
	source = out / 'bad-entry.astra'
	source.write_text('f32 main(){return 0.0;}\n')
	result = subprocess.run([str(compiler), str(source), '-o', str(out / 'bad-entry')], capture_output=True, text=True)
	assert result.returncode == 1 and 'main must return int' in result.stderr and not (out / 'bad-entry').exists()
	rows.append({'f32_main_rejected': True})
	(out / 'results.json').write_text(json.dumps(rows, indent='\t') + '\n')
	print(json.dumps({'runtime_fixtures': len(FIXTURES), 'matrix_pairs': pairs, 'exact_rational_checks': checks, 'f32_main_rejected': True}), flush=True)


if __name__ == '__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
