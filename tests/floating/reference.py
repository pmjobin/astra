# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent exact rational reference for the two Astra floating formats.

Production searches decimal midpoint intervals; this reference quantizes rational
numerator/denominator with quotient/remainder. No host floating arithmetic.
"""
from fractions import Fraction
import re


class Format:
	def __init__(self, width):
		assert width in (32, 64)
		self.width = width
		self.fraction = 23 if width == 32 else 52
		self.bias = 127 if width == 32 else 1023
		self.minimum_unit = 1 - self.bias - self.fraction
		self.sign = 1 << (width - 1)
		self.hidden = 1 << self.fraction
		self.infinity = (2 * self.bias + 1) << self.fraction
		self.nan = self.infinity | (self.hidden >> 1)

	def magnitude(self, bits):
		return bits & (self.sign - 1)

	def is_nan(self, bits):
		return self.magnitude(bits) > self.infinity

	def round(self, number):
		if number == 0:
			return 0
		sign = self.sign if number < 0 else 0
		n, d = abs(number).numerator, number.denominator
		e = n.bit_length() - d.bit_length()
		if (n < d << e) if e >= 0 else (n << -e < d):
			e -= 1
		unit = max(e - self.fraction, self.minimum_unit)
		if unit < 0:
			n <<= -unit
		else:
			d <<= unit
		q, r = divmod(n, d)
		q += 2 * r > d or (2 * r == d and q % 2 != 0)
		if q >= 2 * self.hidden:
			q >>= 1
			unit += 1
		if unit > self.bias - self.fraction:
			return sign | self.infinity
		if q < self.hidden:
			assert unit == self.minimum_unit
			return sign | q
		return sign | ((unit + self.bias + self.fraction) << self.fraction) | (q - self.hidden)

	def value(self, bits):
		magnitude = self.magnitude(bits)
		assert magnitude < self.infinity
		field, fraction = magnitude >> self.fraction, magnitude & (self.hidden - 1)
		power = field - self.bias - self.fraction if field else self.minimum_unit
		significand = fraction | (self.hidden if field else 0)
		number = Fraction(significand << power, 1) if power >= 0 else Fraction(significand, 1 << -power)
		return -number if bits & self.sign else number

	def literal(self, bits):
		assert not self.is_nan(bits)
		magnitude = self.magnitude(bits)
		text = '1e1000' if magnitude == self.infinity else spelling(abs(self.value(bits)))
		return '-' + text if bits & self.sign else text

	def arithmetic(self, op, a, b):
		if self.is_nan(a) or self.is_nan(b):
			return self.nan
		if op == '-':
			return self.arithmetic('+', a, b ^ self.sign)
		x, y = self.magnitude(a), self.magnitude(b)
		sign = (a ^ b) & self.sign
		if op == '+':
			if x == self.infinity or y == self.infinity:
				return self.nan if x == y and sign else a if x == self.infinity else b
			if x == y == 0:
				return (a & b) & self.sign
			return self.round(self.value(a) + self.value(b))
		if op == '*':
			if (x == self.infinity and y == 0) or (y == self.infinity and x == 0):
				return self.nan
			if x == self.infinity or y == self.infinity:
				return sign | self.infinity
			if x == 0 or y == 0:
				return sign
			return self.round(self.value(a) * self.value(b))
		assert op == '/'
		if (x == y == 0) or (x == y == self.infinity):
			return self.nan
		if x == self.infinity or y == 0:
			return sign | self.infinity
		if y == self.infinity or x == 0:
			return sign
		return self.round(self.value(a) / self.value(b))

	def compare(self, op, a, b):
		if self.is_nan(a) or self.is_nan(b):
			return op == '!='
		def key(bits):
			if self.magnitude(bits) == self.infinity:
				return (-1 if bits & self.sign else 1, Fraction(0))
			return (0, self.value(bits))
		x, y = key(a), key(b)
		return {'==': x == y, '!=': x != y, '<': x < y, '<=': x <= y, '>': x > y, '>=': x >= y}[op]

	def convert(self, bits, destination):
		if self.is_nan(bits):
			return destination.nan
		sign = destination.sign if bits & self.sign else 0
		if self.magnitude(bits) == self.infinity:
			return sign | destination.infinity
		if self.magnitude(bits) == 0:
			return sign
		return destination.round(self.value(bits))


BINARY32 = Format(32)
BINARY64 = Format(64)


def decimal_value(text):
	mantissa, *exponent = re.split('[eE]', text)
	digits = mantissa.replace('.', '')
	power = int(exponent[0]) if exponent else 0
	power -= len(mantissa.split('.')[1]) if '.' in mantissa else 0
	return Fraction(int(digits) * 10 ** power, 1) if power >= 0 else Fraction(int(digits), 10 ** -power)


def spelling(number):
	n, d = number.numerator, number.denominator
	k = d.bit_length() - 1
	assert d == 1 << k
	return f'{n * 5 ** k}e-{k}'
