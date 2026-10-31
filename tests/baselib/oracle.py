# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bit/rational expectations. No host floating parsing, arithmetic or libm oracle."""
from fractions import Fraction
from random import Random


class Format:
	def __init__(self, width):
		self.width = width
		self.fraction = 23 if width == 32 else 52
		self.bias = 127 if width == 32 else 1023
		self.sign = 1 << (width - 1)
		self.inf = ((1 << (width - self.fraction - 1)) - 1) << self.fraction
		self.maximum = self.inf - 1
		self.quiet = 1 << (self.fraction - 1)

	def category(self, bits):
		magnitude = bits & (self.sign - 1)
		return 3 if magnitude > self.inf else 2 if magnitude == self.inf else 1

	def rational(self, bits):
		assert self.category(bits) == 1
		exponent = (bits & (self.sign - 1)) >> self.fraction
		mantissa = bits & ((1 << self.fraction) - 1)
		if exponent:
			mantissa += 1 << self.fraction
		power = (exponent if exponent else 1) - self.bias - self.fraction
		value = Fraction(mantissa << max(power, 0), 1 << max(-power, 0))
		return -value if bits & self.sign else value

	def less(self, a, b):
		if self.category(a) == 3 or self.category(b) == 3:
			return False
		if (a & (self.sign - 1)) == 0 and (b & (self.sign - 1)) == 0:
			return False
		key = lambda x: (~x & ((1 << self.width) - 1)) if x & self.sign else x | self.sign
		return key(a) < key(b)

	def select(self, a, b, maximum=False):
		if self.category(a) == 3:
			return a
		if self.category(b) == 3:
			return b
		return b if (self.less(a, b) if maximum else self.less(b, a)) else a

	def round_positive(self, value, square=False):
		# Binary search representable nonnegative values. For sqrt compare exact squares.
		low, high = 0, self.maximum
		while low < high:
			middle = (low + high + 1) // 2
			rational = self.rational(middle)
			if (rational * rational if square else rational) <= value:
				low = middle
			else:
				high = middle - 1
		if low == self.maximum:
			return low
		midpoint = (self.rational(low) + self.rational(low + 1)) / 2
		boundary = midpoint * midpoint if square else midpoint
		return low + (value > boundary or (value == boundary and low % 2 != 0))

	def encode_integer(self, value, negative_zero=False):
		return self.round_positive(Fraction(abs(value))) | (self.sign if value < 0 or (value == 0 and negative_zero) else 0)

	def math(self, operation, bits):
		category = self.category(bits)
		if category == 3:
			return None  # NaN classification, deliberately no payload expectation.
		if operation == 'abs':
			return bits & (self.sign - 1)
		if category == 2:
			return None if operation == 'sqrt' and bits & self.sign else bits
		value = self.rational(bits)
		if operation == 'sqrt':
			return None if value < 0 else bits if value == 0 else self.round_positive(value, square=True)
		if operation == 'floor':
			integer = value.numerator // value.denominator
		elif operation == 'ceil':
			integer = -(-value.numerator // value.denominator)
		else:
			integer = abs(value.numerator) // value.denominator * (-1 if value < 0 else 1)
		return self.encode_integer(integer, bool(bits & self.sign))

	def patterns(self):
		one = self.bias << self.fraction
		magnitudes = [0, 1, 2, (1 << self.fraction) - 1, 1 << self.fraction, (1 << self.fraction) + 1, one - 1, one, one + 1, self.maximum - 1, self.maximum, self.inf, self.inf | self.quiet | 1, self.inf | self.quiet | 91, self.inf | 1]
		bits = [b | sign for b in magnitudes for sign in [0, self.sign]]
		for value in [2, 3, 4, 9, 16, 25]:
			bits.append(self.encode_integer(value))
		for numerator in [1, 3, 5, 7, -1, -3, -5, -7]:
			bits.append(self.round_positive(Fraction(abs(numerator), 4)) | (self.sign if numerator < 0 else 0))
		random = Random(7100 + self.width)
		bits += [random.randrange(self.inf) | (self.sign if random.randrange(2) else 0) for _ in range(24)]
		return list(dict.fromkeys(bits))


def integer_cases():
	random = Random(7101)
	result = {}
	for name, width, signed in [('i8', 8, True), ('u8', 8, False), ('i16', 16, True), ('u16', 16, False), ('int', 32, True), ('u32', 32, False)]:
		low, high = (-(1 << (width - 1)), (1 << (width - 1)) - 1) if signed else (0, (1 << width) - 1)
		values = [low, high, 0, 1, -1 if signed else high - 1]
		pairs = [(a, b) for a in values for b in values] + [(random.randint(low, high), random.randint(low, high)) for _ in range(128)]
		# u32 uses the existing explicit wrapping int->u32 conversion, never a C unsigned channel.
		channel = lambda x: x if x <= 2147483647 else x - 4294967296
		result[name] = [[channel(a), channel(b), channel(min(a, b)), channel(max(a, b))] for a, b in pairs]
	return result
