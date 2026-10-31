# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent modular integer and rational/bit constant-evaluation oracles."""
from pathlib import Path
from fractions import Fraction
import hashlib
import itertools
import json
import random
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'floating'))
from reference import BINARY32, BINARY64

TYPES = {'i8': (8, True), 'u8': (8, False), 'i16': (16, True), 'u16': (16, False), 'int': (32, True), 'u32': (32, False)}
OPS = ['+', '-', '*', '/', '%', '&', '|', '^', '==', '!=', '<', '<=', '>', '>=']


def integer(name, bits):
	width, signed = TYPES[name]
	return bits - (1 << width) if signed and bits >= 1 << (width - 1) else bits


def integer_result(name, op, a, b):
	width, signed = TYPES[name]
	mask = (1 << width) - 1
	x, y = integer(name, a), integer(name, b)
	if op in ['/', '%']:
		if y == 0:
			return 'trap'
		q = (abs(x) // abs(y)) * (-1 if (x < 0) != (y < 0) else 1)
		v = q if op == '/' else x - q * y
	elif op in ['==', '!=', '<', '<=', '>', '>=']:
		return str({'==': x == y, '!=': x != y, '<': x < y, '<=': x <= y, '>': x > y, '>=': x >= y}[op]).lower()
	else:
		v = {'+': lambda: x + y, '-': lambda: x - y, '*': lambda: x * y, '&': lambda: a & b, '|': lambda: a | b, '^': lambda: a ^ b}[op]()
	return str(integer(name, v & mask))


def patterns(fmt):
	values = {0, 1, 2, 3, fmt.hidden - 1, fmt.hidden, fmt.hidden + 1, fmt.infinity - 1, fmt.infinity, fmt.nan, fmt.nan | 71}
	for exponent in [1, 2, fmt.bias - 24, fmt.bias - 1, fmt.bias, fmt.bias + 1, fmt.bias + 24, 2 * fmt.bias - 1, 2 * fmt.bias]:
		for frac in [0, 1, fmt.hidden // 2, fmt.hidden - 1]:
			values.add((exponent << fmt.fraction) | frac)
	return sorted(values | {v | fmt.sign for v in values})


def floating_cases(fmt, random_count=3000):
	rng = random.Random(7200 + fmt.width)
	p = patterns(fmt)
	for a, b in itertools.chain(itertools.product(p, p), ((rng.randrange(1 << fmt.width), rng.randrange(1 << fmt.width)) for _ in range(random_count))):
		for op in ['+', '-', '*', '/', '==', '!=', '<', '<=', '>', '>=']:
			yield a, op, b


def rows():
	rng = random.Random(7201)
	for name, (width, signed) in TYPES.items():
		mask = (1 << width) - 1
		p = sorted({0, 1, 2, 3, mask, mask - 1, mask // 2, mask // 2 + 1, mask // 2 + 2})
		pairs = itertools.product(range(256), repeat=2) if width == 8 else itertools.chain(itertools.product(p, p), ((rng.randrange(mask + 1), rng.randrange(mask + 1)) for _ in range(2048)))
		for a, b in pairs:
			for op in OPS:
				yield f'{name} {op} {a:x} {name} {b:x}', integer_result(name, op, a, b), name
		for a in range(256) if width == 8 else [*p, *(rng.randrange(mask + 1) for _ in range(4096))]:
			x = integer(name, a)
			for op, value in [('+', x), ('~', integer(name, a ^ mask)), *([('-', integer(name, (-x) & mask))] if signed else [])]:
				yield f'{name} {op} {a:x}', str(value), 'unary'
			for destination, (dw, ds) in TYPES.items():
				yield f'{name} as {a:x} {destination}', str(integer(destination, x & ((1 << dw) - 1))), 'iconv'
			for fmt in [BINARY32, BINARY64]:
				yield f'{name} as {a:x} f{fmt.width}', f'0x{fmt.round(Fraction(x)):0{fmt.width // 4}x}', 'int-float'
		for a in p:
			for count_type, (cw, cs) in TYPES.items():
				for count in [0, 1, width - 1, width, width + 1, (1 << cw) - 1]:
					c = integer(count_type, count)
					for op in ['<<', '>>']:
						expected = 'trap' if not 0 <= c < width else str(integer(name, ((a << c) if op == '<<' else integer(name, a) >> c) & mask))
						yield f'{name} {op} {a:x} {count_type} {count:x}', expected, 'shifts'
	for fmt in [BINARY32, BINARY64]:
		for a, op, b in floating_cases(fmt):
			expected = str(fmt.compare(op, a, b)).lower() if op in ['==', '!=', '<', '<=', '>', '>='] else f'0x{fmt.arithmetic(op, a, b):0{fmt.width // 4}x}'
			yield f'f{fmt.width} {op} {a:x} f{fmt.width} {b:x}', expected, 'f' + str(fmt.width)
		for a in [*patterns(fmt), *(rng.randrange(1 << fmt.width) for _ in range(4000))]:
			for op, bits in [('+', a), ('-', a ^ fmt.sign)]:
				yield f'f{fmt.width} {op} {a:x}', f'0x{bits:0{fmt.width // 4}x}', 'float-unary'
			destination = BINARY64 if fmt == BINARY32 else BINARY32
			yield f'f{fmt.width} as {a:x} f{destination.width}', f'0x{fmt.convert(a, destination):0{destination.width // 4}x}', 'float-convert'
			for name, (width, signed) in TYPES.items():
				if fmt.magnitude(a) >= fmt.infinity:
					expected = 'trap'
				else:
					x = fmt.value(a)
					n = (abs(x.numerator) // x.denominator) * (-1 if x < 0 else 1)
					lo, hi = (-(1 << (width - 1)), (1 << (width - 1)) - 1) if signed else (0, (1 << width) - 1)
					expected = str(n) if lo <= n <= hi else 'trap'
				yield f'f{fmt.width} as {a:x} {name}', expected, 'float-int'
	for a, b in itertools.product([0, 1], repeat=2):
		for op, value in [('&', a & b), ('|', a | b), ('^', a ^ b), ('==', a == b), ('!=', a != b)]:
			yield f'bool {op} {a:x} bool {b:x}', str(bool(value)).lower(), 'bool'


def main(executable, out):
	out.mkdir(parents=True, exist_ok=True)
	counts = {}; total = 0; digest = hashlib.sha256()
	# One evaluator process per batch, never a Meson process per value.
	iterator = iter(rows())
	while batch := list(itertools.islice(iterator, 32768)):
		data = '\n'.join(r[0] for r in batch) + '\n'
		p = subprocess.run([executable], input=data, capture_output=True, text=True)
		assert p.returncode == 0 and not p.stderr, (p.returncode, p.stderr)
		actual = p.stdout.splitlines(); assert len(actual) == len(batch)
		for (command, expected, category), got in zip(batch, actual):
			assert got == expected, (command, expected, got)
			counts[category] = counts.get(category, 0) + 1
			digest.update((command + '=' + got + '\n').encode()); total += 1
	result = dict(cases=total, categories=counts, sha256=digest.hexdigest(), oracle='Python integers/Fraction quotient-remainder quantization; no host floating arithmetic')
	(out / 'oracle.json').write_text(json.dumps(result, indent='\t') + '\n')
	print(result)


if __name__ == '__main__':
	main(sys.argv[1], Path(sys.argv[2]))
