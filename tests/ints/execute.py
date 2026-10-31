# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Native fixture and independent Python integer-oracle qualification."""
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ['basic', 'literals', 'wrap', 'div', 'compare', 'branch', 'loop', 'struct', 'addressable', 'native-call', 'ownership']
FAMILY = [('i8', 8, True), ('u8', 8, False), ('i16', 16, True), ('u16', 16, False), ('i32', 32, True), ('u32', 32, False)]


def run(argv):
	result = subprocess.run([str(arg) for arg in argv], cwd=ROOT, capture_output=True, text=True)
	if result.returncode:
		raise RuntimeError(f'{argv}: exit {result.returncode}\n{result.stdout}\n{result.stderr}')
	assert result.stdout == '' and result.stderr == '', result


def bindings():
	return [arg for name in ['types', 'api'] for arg in ['--vapi', ROOT / f'tests/resource/fixtures/resource-{name}.vapi']]


def execute(compiler, source, output, options=(), trap=False):
	run([compiler, source, *options, '-o', output])
	result = subprocess.run([str(output)], capture_output=True, text=True)
	assert result.stdout == '' and result.stderr == '', (source, result)
	assert result.returncode < 0 if trap else result.returncode == 0, (source, result.returncode)


def interpret(bits, width, signed):
	return bits - (1 << width) if signed and bits >= (1 << (width - 1)) else bits


def matrix(t, width, signed):
	modulus = 1 << width
	mask = modulus - 1
	mid = modulus // 2
	values = [0, 1, 2, 3, 7, mid - 1, mid, mid + 1, mask - 2, mask - 1, mask]
	pairs = [(a, b) for a in values for b in values]
	state = 0x61427
	for _ in range(32):
		state = (state * 1664525 + 1013904223) % (1 << 32)
		a = state & mask
		state = (state * 1664525 + 1013904223) % (1 << 32)
		pairs.append((a, state & mask))
	ops = [('add', '+'), ('sub', '-'), ('mul', '*'), ('div', '/'), ('rem', '%')]
	predicates = [('lt', '<'), ('le', '<='), ('gt', '>'), ('ge', '>='), ('eq', '=='), ('ne', '!=')]
	lines = ['// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception']
	lines += [f'{t} {name}({t} a, {t} b) {{ return a {op} b; }}' for name, op in ops]
	lines += [f'bool {name}({t} a, {t} b) {{ return a {op} b; }}' for name, op in predicates]
	lines += [f'{t} pos({t} a) {{ return +a; }}']
	if signed:
		lines += [f'{t} neg({t} a) {{ return -a; }}']
	checks = 0
	for i, (a, b) in enumerate(pairs):
		x, y = interpret(a, width, signed), interpret(b, width, signed)
		wrap = lambda n: interpret(n % modulus, width, signed)
		expected = [('add', wrap(x + y)), ('sub', wrap(x - y)), ('mul', wrap(x * y))]
		if y:
			q = abs(x) // abs(y)
			if (x < 0) != (y < 0):
				q = -q
			expected += [('div', wrap(q)), ('rem', x - q * y)]
		lines.append(f'bool check{i}() {{')
		for op, value in expected:
			lines.append(f'\tif ({op}({x}, {y}) != {value}) {{ return false; }}')
		for (op, _), value in zip(predicates, [x < y, x <= y, x > y, x >= y, x == y, x != y]):
			lines.append(f'\tif ({op}({x}, {y}) != {str(value).lower()}) {{ return false; }}')
		lines.append(f'\tif (pos({x}) != {x}) {{ return false; }}')
		if signed:
			lines.append(f'\tif (neg({x}) != {wrap(-x)}) {{ return false; }}')
		lines += ['\treturn true;', '}']
		checks += len(expected) + 7 + int(signed)
		# Keep each function small; each group qualifies native calls/returns too.
	for start in range(0, len(pairs), 16):
		lines.append(f'bool group{start}() {{ return ' + ' && '.join(f'check{i}()' for i in range(start, min(start + 16, len(pairs)))) + '; }')
	lines += ['int main() {']
	for start in range(0, len(pairs), 16):
		lines.append(f'\tif (!group{start}()) {{ return 1; }}')
	lines += ['\treturn 0;', '}']
	return '\n'.join(lines) + '\n', len(pairs), checks


def main(compiler, companion, output):
	output.mkdir(parents=True, exist_ok=True)
	rows = []
	for name in FIXTURES:
		source = ROOT / f'tests/ints/fixtures/ints-{name}.astra'
		options = [*bindings(), '--link-object', companion] if name == 'ownership' else []
		execute(compiler, source, output / name, options)
		rows.append({'fixture': name, 'passed': True})
	for t, width, signed in FAMILY:
		text, pairs, checks = matrix(t, width, signed)
		source = output / f'matrix-{t}.astra'
		source.write_text(text)
		execute(compiler, source, output / f'matrix-{t}')
		rows.append({'matrix': t, 'pairs': pairs, 'checks': checks, 'passed': True})
		for name, op in [('div', '/'), ('rem', '%')]:
			source = output / f'trap-{t}-{name}.astra'
			source.write_text(f'{t} zero() {{ return 0; }} {t} f({t} x, {t} y) {{ return x {op} y; }} int main() {{ if (f(1, zero()) == 1) {{ return 1; }} return 2; }}\n')
			execute(compiler, source, output / source.stem, trap=True)
			rows.append({'trap': f'{t}-{name}', 'abnormal_termination': True})
	for t in ['u32', 'i16', 'u8']:
		source = output / f'entry-{t}.astra'
		source.write_text(f'{t} main() {{ return 0; }}\n')
		result = subprocess.run([str(compiler), str(source), '-o', str(output / source.stem)], capture_output=True, text=True)
		assert result.returncode == 1 and 'main must return int' in result.stderr
		assert not (output / source.stem).exists()
		rows.append({'rejected_entry': t})
	(output / 'results.json').write_text(json.dumps(rows, indent='\t') + '\n')
	print(json.dumps({'workloads': len(rows), 'runtime_oracle_checks': sum(row.get('checks', 0) for row in rows), 'zero_traps': 12}), flush=True)


if __name__ == '__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
