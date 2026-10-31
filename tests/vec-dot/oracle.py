# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact, host-float-free test authorities for the four dot/MAC modes."""
from fractions import Fraction
from pathlib import Path
import importlib.util
import json
import random
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('astra_f32_scalar_oracle', ROOT / 'tests/f32/oracle.py')
scalar = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scalar)
TYPES = {'i8': (8, True), 'u8': (8, False), 'i16': (16, True), 'u16': (16, False), 'int': (32, True), 'u32': (32, False)}
SIGN = 0x80000000
INF = 0x7f800000
NAN = 0x7fc00000


def integer_value(bits, source):
	width, signed = TYPES[source]
	assert 0 <= bits < 1 << width
	return bits - (1 << width) if signed and bits >= 1 << (width - 1) else bits


def integer_dot(a, b, source, destination, accumulator=None):
	assert len(a) == len(b) and TYPES[destination][0] >= TYPES[source][0]
	# Python integers carry the entire mathematical sum, including u32*u32
	# sums exceeding 64 bits. Only the final result is reduced modulo D.
	total = 0 if accumulator is None else integer_value(accumulator, destination)
	total += sum(integer_value(x, source) * integer_value(y, source) for x, y in zip(a, b))
	return total % (1 << TYPES[destination][0])


def modular_reductions(a, b, source, destination, accumulator=0):
	width = TYPES[destination][0]
	modulus = 1 << width
	# Independent backend-style source conversion, product at D width,
	# then sequential/balanced modular reductions; no signed host overflow.
	def extend(bits):
		w, signed = TYPES[source]
		return bits + (modulus - (1 << w) if signed and bits >= 1 << (w - 1) else 0)
	products = [(extend(x) * extend(y)) % modulus for x, y in zip(a, b)]
	seq = accumulator
	for product in products:
		seq = (seq + product) % modulus
	tree = products
	while len(tree) > 1:
		tree = [(tree[i] + (tree[i + 1] if i + 1 < len(tree) else 0)) % modulus for i in range(0, len(tree), 2)]
	return seq, (accumulator + tree[0]) % modulus


def is_nan(bits):
	return bits & 0x7fffffff > INF


def finite_value(bits):
	assert bits & 0x7fffffff < INF
	return (-1 if bits & SIGN else 1) * scalar.value(bits & 0x7fffffff)


def rounded(exact, negative_zero=False):
	return scalar.round_binary32(abs(exact)) | (SIGN if exact < 0 or exact == 0 and negative_zero else 0)


def f32_mul(a, b):
	x, y = a & 0x7fffffff, b & 0x7fffffff
	sign = (a ^ b) & SIGN
	if is_nan(a) or is_nan(b) or x == INF and y == 0 or y == INF and x == 0:
		return NAN
	if x == INF or y == INF:
		return INF | sign
	return rounded(finite_value(a) * finite_value(b), bool(sign))


def f32_add(a, b):
	x, y = a & 0x7fffffff, b & 0x7fffffff
	if is_nan(a) or is_nan(b) or x == y == INF and (a ^ b) & SIGN:
		return NAN
	if x == INF:
		return a
	if y == INF:
		return b
	return rounded(finite_value(a) + finite_value(b), a == b == SIGN)


def f32_dot(a, b, accumulator=0):
	assert len(a) == len(b)
	products = [f32_mul(x, y) for x, y in zip(a, b)]
	for product in products:
		accumulator = f32_add(accumulator, product)
	return accumulator


def literal(bits):
	if is_nan(bits):
		return '(0.0/0.0)'
	magnitude = bits & 0x7fffffff
	return ('-' if bits & SIGN else '') + ('1e100' if magnitude == INF else scalar.spelling(scalar.value(magnitude)))


def integer_cases():
	rng = random.Random(0xD071)
	for source, (width, signed) in TYPES.items():
		maxbits = (1 << width) - 1
		boundary = [0, 1, 2, (1 << (width - 1)) - 1, 1 << (width - 1), maxbits - 1, maxbits]
		for lanes in [2, 4, 8, 16]:
			if width * lanes > 128:
				continue
			for destination, (dw, ds) in TYPES.items():
				if dw < width:
					continue
				for row in range(24):
					if row < 7:
						a = [boundary[row]] * lanes
						b = [boundary[(row + i) % 7] for i in range(lanes)]
					elif row == 7:
						a = b = [maxbits] * lanes
					else:
						a = [rng.randrange(1 << width) for _ in range(lanes)]
						b = [rng.randrange(1 << width) for _ in range(lanes)]
					c = rng.randrange(1 << dw)
					yield source, destination, a, b, c


def f32_cases():
	rng = random.Random(0xF32D071)
	selected = [0, SIGN, 1, SIGN | 1, 2, 0x7fffff, 0x800000, 0x3f000000, 0x3f800000, 0x3f800001, 0x3f7ffffe, 0x4b800000, 0xcb800000, 0x7f7fffff, INF, INF | SIGN, NAN]
	for lanes in [2, 4]:
		# Per-product/per-addition NaNs, infinities, subnormals and zero signs.
		for i, x in enumerate(selected):
			for y in selected:
				yield [x] + [0] * (lanes - 1), [y] + [0] * (lanes - 1), selected[(i + 3) % len(selected)]
		for _ in range(128):
			yield [rng.getrandbits(32) for _ in range(lanes)], [rng.getrandbits(32) for _ in range(lanes)], rng.getrandbits(32)
		yield [SIGN] * lanes, [0x3f800000] * lanes, SIGN
		yield [1] * lanes, [0x3f800000] * lanes, 1
		yield [0x3f800001] + [0] * (lanes - 1), [0x3f7ffffe] + [0] * (lanes - 1), 0xbf800000
		yield [0x4b800000, 0x3f800000] + ([0xcb800000, 0x3f800000] if lanes == 4 else []), [0x3f800000] * lanes, 0


def test_integer():
	products = 0
	for source in ['i8', 'u8']:
		for a in range(256):
			for b in range(256):
				for destination in TYPES:
					expected = integer_dot([a], [b], source, destination)
					assert modular_reductions([a], [b], source, destination) == (expected, expected)
					products += 1
	vectors = 0
	for source, dest, a, b, c in integer_cases():
		expected = integer_dot(a, b, source, dest, c)
		assert modular_reductions(a, b, source, dest, c) == (expected, expected)
		assert integer_dot(a[::-1], b[::-1], source, dest, c) == expected
		assert integer_dot(a, b, source, dest, 0) == integer_dot(a, b, source, dest)
		vectors += 1
	assert integer_dot([255] * 4, [1] * 4, 'i8', 'u16') == 65532
	assert integer_dot([255] * 4, [1] * 4, 'u8', 'u16') == 1020
	assert integer_dot([0xffffffff] * 4, [0xffffffff] * 4, 'u32', 'u32') == 4
	return {'exhaustive_8bit_products': products, 'vector_rows': vectors, 'sequential_tree_exact_and_permutation': True}


def test_f32():
	one = 0x3f800000
	a, b = [0x4b800000, one, 0xcb800000, one], [one] * 4
	assert f32_dot(a, b) == one
	alternative = f32_add(f32_add(a[0], a[2]), f32_add(a[1], a[3]))
	assert alternative == 0x40000000
	assert f32_dot([a[i] for i in [0, 2, 1, 3]], b) == alternative
	x, y, c = 0x3f800001, 0x3f7ffffe, 0xbf800000
	assert f32_mul(x, y) == one and f32_dot([x, 0], [y, 0], c) == 0
	fused = rounded(finite_value(x) * finite_value(y) + finite_value(c))
	assert fused == 0xa8800000 and fused != 0  # -2^-46
	assert f32_dot([SIGN] * 4, b) == 0
	assert f32_dot([SIGN] * 4, b, SIGN) == SIGN
	assert f32_dot([1, 1], [one, one]) == 2
	assert f32_dot([1, 0], [0x3f000000, one]) == 0  # underflow ties-even
	assert f32_dot([3, 0], [0x3f000000, one]) == 2
	assert f32_dot([INF, 0], [one, one]) == INF
	assert is_nan(f32_dot([INF, 0], [0, one]))
	assert is_nan(f32_dot([INF, INF | SIGN], [one, one]))
	assert is_nan(f32_dot([NAN, 0], [one, one]))
	rows = 0
	for a, b, c in f32_cases():
		expected = c
		for x, y in zip(a, b):
			expected = f32_add(expected, f32_mul(x, y))
		assert f32_dot(a, b, c) == expected
		rows += 1
	return {'f32_rows': rows, 'ordered_flagship_bits': '3f800000', 'alternative_tree_bits': '40000000', 'unfused_bits': '00000000', 'fused_counterexample_bits': f'{fused:08x}', 'signed_zero_dot': '00000000', 'signed_zero_mac': '80000000', 'scalar_authority': 'tests/f32/oracle.py exact Fraction quantization'}


if __name__ == '__main__':
	print(json.dumps(test_integer() if sys.argv[1] == 'integer' else test_f32()))
