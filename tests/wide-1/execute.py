# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent Python integer oracle plus an independently compiled C ABI client."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys

MASK = (1 << 64) - 1
MIN = -(1 << 63)
SOURCE = r'''
const u64 WIDE_MAX = 18446744073709551615;
const i64 SIGNED_MIN = -9223372036854775808;
const u64 WIDE_ZERO = WIDE_MAX + 1;
const i64 FLOAT_MIN = -9223372036854775808.0d as i64;
const u64 FLOAT_HIGH = 18446744073709549568.0d as u64;
const u64 ROUNDING_INPUT = 9223372586610589697;
const f32 DIRECT_SINGLE = ROUNDING_INPUT as f32;
extern(C) u64 input_word();
extern(C) int emit_u(u64 value);
extern(C) int emit_i(i64 value);
extern(C) usize size_roundtrip(usize value);
extern(C) isize offset_roundtrip(isize value);
extern(C) int check_export();
extern(C) int emit_f64(f64 value);
extern(C) int emit_f32(f32 value);
export(C) u64 astra_wide_sum(u64 a, u64 b) { return a + b; }
export(C) i64 astra_wide_signed(i64 a) { return a / -1; }
struct Wide { u64 upper; i64 lower; }
int main() {
    if (WIDE_ZERO != 0 || FLOAT_MIN != SIGNED_MIN || FLOAT_HIGH != 18446744073709549568) { return 3; }
    if (DIRECT_SINGLE != 9223373136366403584.0f) { return 4; }
    u64 x = input_word(); i64 s = x as i64;
    emit_u(x + 4294967297); emit_u(x * 1099511628211);
    emit_u(x / 4294967297); emit_u(x % 4294967297);
    emit_u((x ^ 14695981039346656037) >> 31);
    emit_u((x << 63) | (x >> 63));
    emit_i(s / -1); emit_i(s % -1); emit_i(s >> 63);
    emit_u((s as u8) as u64); emit_u((s as i8) as u64);
    Wide w = {upper=x, lower=s}; emit_u(w.upper); emit_i(w.lower);
    u64[2] words = {0, 0}; u64 index = 1; words[index] = x;
    emit_u(words[index]);
    owned i64[] values = new i64[2]; values[index] = s;
    emit_i(values[index]);
    usize count = 4294967297; emit_u(size_roundtrip(count) as u64);
    isize offset = -4294967297; emit_i(offset_roundtrip(offset) as i64);
    u64 sum = 0; int at = 0;
    while(at < 7) { sum = sum * 3 + x; at = at + 1; }
    emit_u(sum);
    emit_f64(x as f64); emit_f64(s as f64);
    emit_f32(x as f32); emit_f32(s as f32);
    if (check_export() != 0) { return 2; }
    return 0;
}
'''
C_SOURCE = r'''
#include <inttypes.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
_Static_assert(sizeof(int64_t)==8 && sizeof(uint64_t)==8, "fixed widths");
_Static_assert(sizeof(void*)==8 && sizeof(size_t)==8 && sizeof(ptrdiff_t)==8, "LP64 host witness");
uint64_t input_word(void) { return strtoull(getenv("ASTRA_WIDE_INPUT"), NULL, 10); }
double input_float(void) { return strtod(getenv("ASTRA_WIDE_FLOAT"), NULL); }
int emit_u(uint64_t value) { return printf("%" PRIu64 "\n", value) < 0; }
int emit_i(int64_t value) { return printf("%" PRId64 "\n", value) < 0; }
int emit_f64(double value) { uint64_t bits; memcpy(&bits, &value, sizeof bits); return emit_u(bits); }
int emit_f32(float value) { uint32_t bits; memcpy(&bits, &value, sizeof bits); return emit_u(bits); }
size_t size_roundtrip(size_t value) { return value + UINT64_C(4294967296); }
ptrdiff_t offset_roundtrip(ptrdiff_t value) { return value - INT64_C(4294967296); }
extern uint64_t astra_wide_sum(uint64_t, uint64_t);
extern int64_t astra_wide_signed(int64_t);
int check_export(void) {
    return astra_wide_sum(UINT64_MAX, UINT64_C(4294967297)) != UINT64_C(4294967296)
        || astra_wide_signed(INT64_MIN) != INT64_MIN
        || astra_wide_signed(-INT64_C(4294967297)) != INT64_C(4294967297);
}
'''


def signed(x):
	x &= MASK
	return x - (1 << 64) if x >= (1 << 63) else x


def ieee_bits(number, fraction_width, exponent_width):
	"""Round the mathematical integer once, with integer-only ties-even."""
	sign = number < 0
	magnitude = abs(number)
	if not magnitude:
		return 0
	exponent = magnitude.bit_length() - 1
	shift = exponent - fraction_width
	if shift <= 0:
		significand = magnitude << -shift
	else:
		significand, remainder = divmod(magnitude, 1 << shift)
		half = 1 << (shift - 1)
		if remainder > half or remainder == half and significand & 1:
			significand += 1
		if significand == 1 << (fraction_width + 1):
			significand >>= 1
			exponent += 1
	bias = (1 << (exponent_width - 1)) - 1
	return ((int(sign) << (fraction_width + exponent_width))
		| ((exponent + bias) << fraction_width)
		| (significand & ((1 << fraction_width) - 1)))


def expected(x):
	s = signed(x)
	narrow = x & 255
	i8 = narrow - 256 if narrow >= 128 else narrow
	total = 0
	for _ in range(7):
		total = (total * 3 + x) & MASK
	f64 = lambda n: ieee_bits(n, 52, 11)
	f32 = lambda n: ieee_bits(n, 23, 8)
	values = [(x + 4294967297) & MASK, (x * 1099511628211) & MASK,
		x // 4294967297, x % 4294967297,
		(x ^ 14695981039346656037) >> 31,
		((x << 63) | (x >> 63)) & MASK,
		signed(-s), 0, -1 if s < 0 else 0,
		narrow, i8 & MASK, x, s, x, s,
		8589934593, -8589934593, total, f64(x), f64(s), f32(x), f32(s)]
	return ''.join(f'{v}\n' for v in values).encode()


def run(argv, **kw):
	result = subprocess.run([str(v) for v in argv], capture_output=True, **kw)
	assert result.returncode == 0, (argv, result.returncode, result.stdout, result.stderr)
	return result


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	cc = shutil.which('cc')
	assert cc
	source = out/'wide.astra'; source.write_text(SOURCE)
	companion = out/'companion.c'; companion.write_text(C_SOURCE)
	obj = out/'companion.o'
	run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', companion, '-o', obj])
	records = []
	inputs = [0, 1, 255, 4294967297, (1 << 53) + 1, (1 << 53) + 3,
		(1 << 63) - 1, 1 << 63, (1 << 63) + (1 << 39) + 1, MASK - 1, MASK]
	for mode in ['-O0', '-O2']:
		binary = out/('wide'+mode)
		run([compiler, mode, source, '--link-object', obj, '-o', binary])
		for x in inputs:
			actual = run([binary], env={**os.environ, 'ASTRA_WIDE_INPUT': str(x)})
			assert actual.stdout == expected(x), (mode, x, actual.stdout, expected(x))
			records.append(dict(mode=mode, input=str(x), output=actual.stdout.decode()))
	negative = {
		'unsigned-overflow': 'u64 f(){return 18446744073709551616;}',
		'signed-overflow': 'i64 f(){return 9223372036854775808;}',
		'signed-underflow': 'i64 f(){return -9223372036854775809;}',
		'implicit-narrow': 'int f(i64 x){return x;}',
		'implicit-sign': 'u64 f(i64 x){return x;}',
		'implicit-size': 'u64 f(usize x){return x;}',
		'usize-array-count': 'void f(usize n){owned u8[] a=new u8[n];}',
		'i64-array-count': 'void f(i64 n){owned u8[] a=new u8[n];}',
		'mixed-wide': 'u64 f(u64 a,i64 b){return a+b;}',
		'wide-vector': 'void f(){i64<4> v=splat(1,4);}',
		'wide-index': 'const u64 INDEX=18446744073709551615;void f(){u64[2] a={0,0};u64 b=a[INDEX];}',
		'wide-shift': 'u64 f(u64 x){return x<<64;}',
	}
	for name, text in negative.items():
		path = out/(name+'.astra'); path.write_text(text)
		result = subprocess.run([str(compiler), '--dump-llvm', str(path)], capture_output=True)
		assert result.returncode != 0 and not result.stdout and result.stderr, (name, result)
	for name, body in {
		'index-trap': 'u64 i=input_word();u8[2] a={0,0};return a[i] as int;',
		'shift-trap': 'u64 i=input_word();u64 x=1;return (x<<i) as int;',
		'divide-trap': 'u64 x=input_word();return (x/0) as int;',
	}.items():
		path = out/(name+'.astra'); path.write_text('extern(C) u64 input_word(); int main(){'+body+'}')
		for mode in ['-O0', '-O2']:
			binary = out/(name+mode)
			# The shared C object has export dependencies, so provide those
			# genuine Astra implementations even for isolated trap witnesses.
			with path.open('a') as f:
				if mode == '-O0':
					f.write('export(C) u64 astra_wide_sum(u64 a,u64 b){return a+b;}export(C) i64 astra_wide_signed(i64 a){return a/-1;}')
			run([compiler, mode, path, '--link-object', obj, '-o', binary])
			result = subprocess.run([str(binary)], env={**os.environ, 'ASTRA_WIDE_INPUT': str(MASK)}, capture_output=True)
			assert result.returncode != 0, (name, mode, result)
			# Dynamic C double inputs keep native conversion guards observable.
	for destination, cases in {
		'i64': [('-9223372036854775808', MIN), ('9223372036854774784', (1 << 63) - 1024),
		('-9223372036854777856', None), ('9223372036854775808', None), ('nan', None), ('inf', None)],
		'u64': [('18446744073709549568', (1 << 64) - 2048), ('-0.5', 0),
		('18446744073709551616', None), ('-1', None), ('nan', None), ('inf', None)],
	}.items():
		path = out/('float-'+destination+'.astra')
		emit = 'emit_i' if destination == 'i64' else 'emit_u'
		path.write_text(f'extern(C) f64 input_float();extern(C) int {emit}({destination} value);'
			f'int main(){{{destination} value=input_float() as {destination};return {emit}(value);}}'
			'export(C) u64 astra_wide_sum(u64 a,u64 b){return a+b;}'
			'export(C) i64 astra_wide_signed(i64 a){return a/-1;}')
		for mode in ['-O0', '-O2']:
			binary = out/('float-'+destination+mode)
			run([compiler, mode, path, '--link-object', obj, '-o', binary])
			for text, value in cases:
				result = subprocess.run([str(binary)], env={**os.environ, 'ASTRA_WIDE_FLOAT': text}, capture_output=True)
				if value is None:
					assert result.returncode != 0 and not result.stdout, (destination, mode, text, result)
				else:
					assert result.returncode == 0 and result.stdout == f'{value}\n'.encode(), (destination, mode, text, result)
	(out/'results.json').write_text(json.dumps(records, indent=2)+'\n')
	print(f'{len(records)} public native/C ABI integer oracles, {len(negative)} static negatives, 6 integer traps, 24 dynamic float conversions')


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
