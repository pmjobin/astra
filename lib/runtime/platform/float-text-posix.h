/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_FLOAT_TEXT_POSIX_H
#define ASTRA_FLOAT_TEXT_POSIX_H
#include <stdint.h>

struct astra_numeric_f32_cell {
	float value;
};

struct astra_numeric_f64_cell {
	double value;
};

/* Positive parse status / negative format error; formats otherwise return count. */
enum astra_numeric_status {
	ASTRA_NUMERIC_INVALID = 1,
	ASTRA_NUMERIC_OVERFLOW = 2,
	ASTRA_NUMERIC_UNDERFLOW = 3,
	ASTRA_NUMERIC_ALLOCATION = 4,
	ASTRA_NUMERIC_ROUNDING = 5,
	ASTRA_NUMERIC_OUTPUT = 6
};

int32_t astra_numeric_format_f32(float value, unsigned char *output, int32_t capacity);
int32_t astra_numeric_format_f64(double value, unsigned char *output, int32_t capacity);
int32_t astra_numeric_parse_f32(const unsigned char *input, int32_t count, struct astra_numeric_f32_cell *output);
int32_t astra_numeric_parse_f64(const unsigned char *input, int32_t count, struct astra_numeric_f64_cell *output);
#endif
