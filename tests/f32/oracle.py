# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Qualify conversion against both exact rational rounding and C strtof.

The rational oracle quantizes numerator/denominator at the binary exponent;
it does not search encodings or compare decimal midpoints like production.
All dependencies are Python standard library / test-only libc.
"""
from fractions import Fraction
from pathlib import Path
import json
import os
import random
import re
import struct
import subprocess
import sys

sys.dont_write_bytecode = True
sys.set_int_max_str_digits(0)


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'floating'))
from reference import BINARY32, decimal_value, spelling

round_binary32 = BINARY32.round
value = BINARY32.value


def corpus():
	rows = []
	def add(text, expected=None):
		rows.append((text, round_binary32(decimal_value(text)) if expected is None else expected))
	for text in ['0.0', '1.0', '1.00', '10e-1', '1E3', '1.25e-4', '123.456E+7', '3.14159265', '1.401298464324817e-45', '1.1754943508222875e-38', '3.4028234663852886e38', '1e100', '1e-100']:
		add(text)
	boundaries = {0, 1, 2, 0x7ffffe, 0x7fffff, 0x800000, 0x3f800000, 0x3f800001, 0x7f7ffffe, 0x7f7fffff}
	for exponent in range(255):
		for fraction in [0, 1, 2, 0x3fffff, 0x7ffffe, 0x7fffff]:
			boundaries.add((exponent << 23) | fraction)
	for lower in sorted(boundaries):
		a = value(lower)
		b = value(lower + 1) if lower < 0x7f7fffff else Fraction(1 << 128)
		mid = (a + b) / 2
		for point, expected in [(a, lower), (mid - (b - a) / (1 << 100), lower), (mid, lower + (lower & 1)), (mid + (b - a) / (1 << 100), lower + 1)]:
			add(spelling(point), expected)
	rng = random.Random(0x61427)
	for _ in range(6000):
		length = rng.choice([1, 7, 9, 17, 25, 50, 113, 114, 200, 500])
		digits = ''.join(str(rng.randrange(10)) for _ in range(length))
		point = rng.randrange(1, length + 1)
		add(digits[:point] + '.' + (digits[point:] or '0') + 'e' + str(rng.randrange(-70, 50) - point))
	for n in [112, 113, 114, 1000, 10000]:
		add('1.000000059604644775390625' + '0' * n + '1', 0x3f800001)
		add('1' + '0' * n + 'e-' + str(n), 0x3f800000)
		add('0.' + '0' * n + '1e' + str(n + 1), 0x3f800000)
		# Exponents large enough to require the bounded early classification path.
	for text, expected in [('1e' + '9' * 10000, 0x7f800000), ('1e-' + '9' * 10000, 0), ('0e' + '9' * 10000, 0)]:
		add(text, expected)
	return rows


def convert(executable, inputs, locale='C'):
	result = subprocess.run([str(executable)], input=inputs, capture_output=True, text=True, env=dict(os.environ, LC_ALL=locale), check=True)
	assert result.stderr == '', result.stderr
	return [int(line, 16) for line in result.stdout.splitlines()]


def main(converter, libc, output):
	rows = corpus()
	inputs = '\n'.join(row[0] for row in rows) + '\n'
	expected = [row[1] for row in rows]
	for authority in [converter, libc]:
		actual = convert(authority, inputs)
		assert len(actual) == len(expected)
		for (text, gold), got in zip(rows, actual):
			assert got == gold, (authority, text, f'{gold:08x}', f'{got:08x}')
	locales = subprocess.run(['locale', '-a'], capture_output=True, text=True, check=True).stdout.splitlines()
	qualified_locales = []
	for locale in ['fr_CA.utf8', 'fr_FR.utf8', 'de_DE.utf8']:
		if locale in locales:
			assert convert(converter, inputs, locale) == expected, locale
			qualified_locales.append(locale)
	witness = '1.00000005960464477539062500000000000000000000000000000001'
	assert round_binary32(decimal_value(witness)) == 0x3f800001
	assert struct.unpack('>I', struct.pack('>f', float(witness)))[0] == 0x3f800000
	result = {'decimal_cases': len(rows), 'midpoint_cases_all_exponents': 255 * 6 * 4, 'independent_oracles': ['Python exact rational quantization', 'libc strtof C locale FE_TONEAREST'], 'non_c_locales': qualified_locales, 'double_rounding_witness_rejected': True}
	output.write_text(json.dumps(result, indent='\t') + '\n')
	print(json.dumps(result), flush=True)


if __name__ == '__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
