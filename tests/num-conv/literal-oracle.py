# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Complete existing decimal corpora through actual suffixed source semantics."""
from pathlib import Path
from fractions import Fraction
import importlib.util
import json
import os
import subprocess
import sys

sys.dont_write_bytecode = True
sys.set_int_max_str_digits(0)
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tests/floating'))
from reference import BINARY32 as F32, BINARY64 as F64


def module(name, path):
	spec = importlib.util.spec_from_file_location(name, path)
	result = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(result)
	return result


def main(compiler, output):
	rows = []
	for fmt, suffix, cases in [(F32, 'f', module('f32_decimal', ROOT/'tests/f32/oracle.py').corpus()), (F64, 'd', [(text.removeprefix('decimal '), bits) for text, bits in module('f64_decimal', ROOT/'tests/f64/oracle.py').decimals()])]:
		for text, bits in cases:
			for letter in [suffix, suffix.upper()]:
				rows.append((text + letter, f'f{fmt.width} 0x{bits:0{fmt.width // 4}x}'))
		for text, bits in [('0.0', 0), ('1.25', fmt.round(Fraction(5, 4)))]:
			rows.append(('-' + text + suffix, f'f{fmt.width} 0x{bits | fmt.sign:0{fmt.width // 4}x}'))
	locales = ['C', 'fr_CA.utf8', 'fr_FR.utf8', 'de_DE.utf8']
	available = subprocess.check_output(['locale', '-a'], text=True).splitlines()
	assert all(locale in available for locale in locales), available
	for locale in locales:
		p = subprocess.run([compiler, '--literals'], input='\n'.join(text for text, _ in rows)+'\n', capture_output=True, text=True, env=dict(os.environ, LC_ALL=locale), check=True)
		assert not p.stderr, p.stderr
		actual = p.stdout.splitlines()
		assert len(actual) == len(rows)
		for (text, expected), value in zip(rows, actual):
			assert value == expected, (text, value, expected, locale)
		print(f'{locale}: {len(rows)} exact suffixed source constants', flush=True)
	result = dict(cases=len(rows), f32_cases=sum(expected.startswith('f32') for _, expected in rows), f64_cases=sum(expected.startswith('f64') for _, expected in rows), locales=locales, authority='independent exact rational quantization against actual semantic literal construction')
	output.write_text(json.dumps(result, indent='\t')+'\n')


if __name__ == '__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
