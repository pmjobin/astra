/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "failure.h"
#include <float.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if !defined(__x86_64__) || !defined(__linux__)
#error "Astra base floating diagnostics require qualified CABI-FP x86-64 Linux"
#endif
_Static_assert(CHAR_BIT == 8 && sizeof(float) == 4 && FLT_RADIX == 2 && FLT_MANT_DIG == 24 && FLT_MAX_EXP == 128, "requires binary32 C float");
_Static_assert(sizeof(double) == 8 && DBL_MANT_DIG == 53 && DBL_MAX_EXP == 1024, "requires binary64 C double");

static _Noreturn void astra_base_terminate(void) {
	/* Best effort: neither a failed write nor failed flush permits recovery. */
	(void)fflush(stderr);
	abort();
}

_Noreturn void astra_base_fail(int32_t kind, int32_t code) {
	const char *family = kind == 1 ? "assertion" : kind == 2 ? "clamp bounds"
	                                                         : "contract";
	(void)fprintf(stderr, "astra base: %s failure kind=%" PRId32 " code=%" PRId32 "\n", family, kind, code);
	astra_base_terminate();
}

_Noreturn void astra_base_equal_i32(int32_t code, int32_t actual, int32_t expected) {
	(void)fprintf(stderr, "astra base: equality i32 code=%" PRId32 " expected=%" PRId32 " actual=%" PRId32 "\n", code, expected, actual);
	astra_base_terminate();
}

_Noreturn void astra_base_equal_f32(int32_t code, float actual, float expected) {
	uint32_t actual_bits, expected_bits;
	memcpy(&actual_bits, &actual, sizeof(actual_bits));
	memcpy(&expected_bits, &expected, sizeof(expected_bits));
	(void)fprintf(stderr, "astra base: equality f32 code=%" PRId32 " expected=%.9g actual=%.9g expected_bits=0x%08" PRIx32 " actual_bits=0x%08" PRIx32 "\n", code, (double)expected, (double)actual, expected_bits, actual_bits);
	astra_base_terminate();
}

_Noreturn void astra_base_equal_f64(int32_t code, double actual, double expected) {
	uint64_t actual_bits, expected_bits;
	memcpy(&actual_bits, &actual, sizeof(actual_bits));
	memcpy(&expected_bits, &expected, sizeof(expected_bits));
	(void)fprintf(stderr, "astra base: equality f64 code=%" PRId32 " expected=%.17g actual=%.17g expected_bits=0x%016" PRIx64 " actual_bits=0x%016" PRIx64 "\n", code, expected, actual, expected_bits, actual_bits);
	astra_base_terminate();
}
