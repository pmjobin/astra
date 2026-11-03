/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "float-text-posix.h"
#include <errno.h>
#include <fenv.h>
#include <float.h>
#include <limits.h>
#include <locale.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if !defined(__linux__) || !defined(__x86_64__) || !defined(__GLIBC__)
#error "Astra float text provider is qualified only for GNU x86-64 Linux"
#endif
_Static_assert(CHAR_BIT == 8 && sizeof(float) == 4 && sizeof(double) == 8,
               "numeric text requires octets and binary32/binary64");
_Static_assert(FLT_RADIX == 2 && FLT_MANT_DIG == 24 && DBL_MANT_DIG == 53,
               "numeric text requires IEEE binary32/binary64 precision");
_Static_assert(sizeof(size_t) == 8 && sizeof(int32_t) == 4,
               "numeric text provider requires LP64 counted I32 transport");

static int32_t format_value(double value, int precision, unsigned char *output, int32_t capacity) {
	if (output == NULL || capacity < 32) {
		return -ASTRA_NUMERIC_OUTPUT;
	}
	if (fegetround() != FE_TONEAREST) {
		return -ASTRA_NUMERIC_ROUNDING;
	}
	const char *special = isnan(value) ? "nan" : isinf(value) ? (signbit(value) ? "-inf" : "inf")
	                                                          : NULL;
	if (special != NULL) {
		size_t count = strlen(special);
		memcpy(output, special, count + 1);
		return (int32_t)count;
	}
	locale_t numeric = newlocale(LC_NUMERIC_MASK, "C", (locale_t)0);
	if (numeric == (locale_t)0) {
		return -ASTRA_NUMERIC_ALLOCATION;
	}
	locale_t previous = uselocale(numeric);
	if (previous == (locale_t)0) {
		freelocale(numeric);
		return -ASTRA_NUMERIC_ALLOCATION;
	}
	int count = snprintf((char *)output, (size_t)capacity, "%.*g", precision, value);
	/* Restoring a previously valid locale cannot allocate. */
	if (uselocale(previous) == (locale_t)0) {
		abort();
	}
	freelocale(numeric);
	return count < 0 || count >= capacity ? -ASTRA_NUMERIC_OUTPUT : count;
}

int32_t astra_numeric_format_f32(float value, unsigned char *output, int32_t capacity) {
	return format_value((double)value, 9, output, capacity);
}

int32_t astra_numeric_format_f64(double value, unsigned char *output, int32_t capacity) {
	return format_value(value, 17, output, capacity);
}

static int digit(unsigned char value) {
	return value >= '0' && value <= '9';
}

/* Validate counted ASCII before libc sees a terminator, whitespace, hex, payload,
 * locale decimal separator, or a truncated prefix. Track nonzero mantissa digits
 * independently from exponent digits so exact signed zero is never underflow. */
static int decimal(const unsigned char *input, int32_t count, int *nonzero) {
	int32_t index = 0;
	if (index < count && (input[index] == '-' || input[index] == '+')) {
		index++;
	}
	int digits = 0;
	*nonzero = 0;
	while (index < count && digit(input[index])) {
		digits = 1;
		*nonzero |= input[index++] != '0';
	}
	if (index < count && input[index] == '.') {
		index++;
		while (index < count && digit(input[index])) {
			digits = 1;
			*nonzero |= input[index++] != '0';
		}
	}
	if (!digits) {
		return 0;
	}
	if (index < count && (input[index] == 'e' || input[index] == 'E')) {
		index++;
		if (index < count && (input[index] == '-' || input[index] == '+')) {
			index++;
		}
		int32_t exponent = index;
		while (index < count && digit(input[index])) {
			index++;
		}
		if (index == exponent) {
			return 0;
		}
	}
	return index == count;
}

static int special(const unsigned char *input, int32_t count) {
	if (count == 3 && memcmp(input, "nan", 3) == 0) {
		return 1;
	}
	if (count == 3 && memcmp(input, "inf", 3) == 0) {
		return 2;
	}
	if (count == 4 && memcmp(input, "+inf", 4) == 0) {
		return 2;
	}
	if (count == 4 && memcmp(input, "-inf", 4) == 0) {
		return 3;
	}
	return 0;
}

#define PARSE(SUFFIX, TYPE, STRTO, CELL) \
int32_t astra_numeric_parse_##SUFFIX(const unsigned char *input, int32_t count, struct CELL *output) { \
	if (input == NULL || output == NULL || count <= 0) { return ASTRA_NUMERIC_INVALID; } \
	if (fegetround() != FE_TONEAREST) { return ASTRA_NUMERIC_ROUNDING; } \
	int kind = special(input, count); \
	if (kind != 0) { output->value = kind == 1 ? (TYPE)NAN : kind == 2 ? (TYPE)INFINITY : (TYPE)-INFINITY; return 0; } \
	int nonzero; \
	if (!decimal(input, count, &nonzero)) { return ASTRA_NUMERIC_INVALID; } \
	char *terminated = malloc((size_t)count + 1); \
	if (terminated == NULL) { return ASTRA_NUMERIC_ALLOCATION; } \
	memcpy(terminated, input, (size_t)count); terminated[count] = 0; \
	locale_t numeric = newlocale(LC_NUMERIC_MASK, "C", (locale_t)0); \
	if (numeric == (locale_t)0) { free(terminated); return ASTRA_NUMERIC_ALLOCATION; } \
	errno = 0; char *end; TYPE value = STRTO(terminated, &end, numeric); \
	int status = errno != 0 && errno != ERANGE ? (errno == ENOMEM ? ASTRA_NUMERIC_ALLOCATION : ASTRA_NUMERIC_INVALID) : \
		end != terminated + count ? ASTRA_NUMERIC_INVALID : \
		isinf(value) ? ASTRA_NUMERIC_OVERFLOW : (value == 0 && nonzero) ? ASTRA_NUMERIC_UNDERFLOW : 0; \
	freelocale(numeric); free(terminated); \
	if (status == 0) { output->value = value; } \
	return status; \
}
PARSE(f32, float, strtof_l, astra_numeric_f32_cell)
PARSE(f64, double, strtod_l, astra_numeric_f64_cell)
#undef PARSE
