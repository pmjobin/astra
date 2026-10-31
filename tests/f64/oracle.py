# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact deterministic binary64 decimal and cross-format conversion matrices."""
from fractions import Fraction
from pathlib import Path
import json
import os
import random
import subprocess
import sys
import time

sys.dont_write_bytecode = True
sys.set_int_max_str_digits(0)
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'floating'))
from reference import BINARY32 as F32, BINARY64 as F64, decimal_value, spelling


def decimals():
	rows = []
	def add(text, expected=None):
		rows.append(('decimal ' + text, F64.round(decimal_value(text)) if expected is None else expected))
	for text in ['0.0', '1.0', '1.0000000000000002', '9007199254740993.0', '1.000000059604644775390625', '4.9406564584124654e-324', '2.2250738585072014e-308', '1.7976931348623157e308', '1e309', '1e-325']:
		add(text)
	boundaries = {0, 1, 2, F64.hidden - 2, F64.hidden - 1, F64.hidden, F64.bias << 52, (F64.bias << 52) + 1, F64.infinity - 2, F64.infinity - 1}
	boundaries.update(field << 52 for field in range(2047))
	for field in [0, 1, 2, 1022, 1023, 1024, 1075, 2045, 2046]:
		boundaries.update((field << 52) | frac for frac in [1, 2, (1 << 51) - 1, (1 << 52) - 2, (1 << 52) - 1])
	for lower in sorted(boundaries):
		a = F64.value(lower)
		b = F64.value(lower + 1) if lower < F64.infinity - 1 else Fraction(1 << 1024)
		mid = (a + b) / 2
		for point, expected in [(a, lower), (mid - (b - a) / (1 << 100), lower), (mid, lower + (lower & 1)), (mid + (b - a) / (1 << 100), lower + 1)]:
			add(spelling(point), expected)
	for power in range(-330, 312):
		add('1e' + str(power))
	rng = random.Random(0xF641)
	for _ in range(6000):
		length = rng.choice([1, 7, 17, 25, 53, 113, 500, 768, 769, 1100])
		digits = ''.join(str(rng.randrange(10)) for _ in range(length))
		point = rng.randrange(1, length + 1)
		add(digits[:point] + '.' + (digits[point:] or '0') + 'e' + str(rng.randrange(-345, 325) - point))
	tie = '1.00000000000000011102230246251565404236316680908203125'
	for n in [767, 768, 769, 1000, 10000]:
		add(tie + '0' * n + '1', (F64.bias << 52) + 1)
		add('1' + '0' * n + 'e-' + str(n), F64.bias << 52)
		add('0.' + '0' * n + '1e' + str(n + 1), F64.bias << 52)
	for text, bits in [('1e' + '9' * 10000, F64.infinity), ('1e-' + '9' * 10000, 0), ('0e' + '9' * 10000, 0)]:
		add(text, bits)
	return rows


def conversions():
	rng = random.Random(0x3264)
	patterns = {sign | (field << 23) | frac for sign in [0, F32.sign] for field in range(256) for frac in [0, 1, 2, (1 << 22) - 1, (1 << 23) - 2, (1 << 23) - 1]}
	patterns.update((F32.bias << 23) + i for i in range(16384))
	patterns.update(rng.randrange(1 << 32) for _ in range(16000))
	# Include every accepted existing F32 decimal oracle vector.
	sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'f32'))
	from oracle import corpus
	patterns.update(bits for _, bits in corpus())
	wide = [('widen ' + f'{bits:08x}', F32.convert(bits, F64)) for bits in sorted(patterns)]
	narrow_patterns = {F32.convert(bits, F64) for bits in patterns}
	for lower in [0, 1, 2, 0x7ffffe, 0x7fffff, 0x800000, 0x3f7fffff, 0x3f800000, 0x3f800001, 0x7f7ffffe, 0x7f7fffff]:
		a = F32.value(lower)
		b = F32.value(lower + 1) if lower < F32.infinity - 1 else Fraction(1 << 128)
		tie = F64.round((a + b) / 2)
		for delta in [-1, 0, 1]:
			for sign in [0, F64.sign]:
				narrow_patterns.add((tie + delta) | sign)
	narrow_patterns.update(rng.randrange(1 << 64) for _ in range(16000))
	narrow_patterns.update([0, F64.sign, 1, F64.hidden - 1, F64.hidden, F64.infinity - 1, F64.infinity, F64.sign | F64.infinity, F64.nan, F64.infinity | 1])
	narrow = [('narrow ' + f'{bits:016x}', F64.convert(bits, F32)) for bits in sorted(narrow_patterns)]
	return wide, narrow


def invoke(converter, rows, locale='C'):
	p = subprocess.run([str(converter)], input='\n'.join(text for text, _ in rows) + '\n', text=True, capture_output=True, env=dict(os.environ, LC_ALL=locale), check=True)
	assert not p.stderr, p.stderr
	actual = [int(line, 16) for line in p.stdout.splitlines()]
	assert len(actual) == len(rows)
	for (text, expected), got in zip(rows, actual):
		assert got == expected, (text, hex(expected), hex(got))
	return actual


def main(converter, output):
	started = time.monotonic()
	rows = decimals()
	print(f"decimal cases: {len(rows)}", flush=True)
	invoke(converter, rows)
	locales = subprocess.check_output(['locale', '-a'], text=True).splitlines()
	qualified = []
	for locale in ['fr_CA.utf8', 'fr_FR.utf8', 'de_DE.utf8']:
		if locale in locales:
			invoke(converter, rows, locale)
			qualified.append(locale)
			print(f"qualified locale: {locale}", flush=True)
	print("decimal cases complete", flush=True)
	wide, narrow = conversions()
	actual_wide = invoke(converter, wide)
	invoke(converter, narrow)
	roundtrip = [('narrow ' + f'{bits:016x}', int(text.split()[1], 16)) for (text, _), bits in zip(wide, actual_wide) if not F32.is_nan(int(text.split()[1], 16))]
	invoke(converter, roundtrip)
	result = dict(decimal_cases=len(rows), all_binary64_finite_exponent_classes=2047, random_decimal_cases=6000, non_c_locales=qualified, widening_cases=len(wide), narrowing_cases=len(narrow), finite_infinite_zero_exact_roundtrips=len(roundtrip), authority='shared exact integer/rational quantization; no host float or double', seconds=round(time.monotonic() - started, 2))
	output.write_text(json.dumps(result, indent='\t') + '\n')
	print(json.dumps(result), flush=True)


if __name__ == '__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
