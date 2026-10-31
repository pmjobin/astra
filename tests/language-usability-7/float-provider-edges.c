/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Provider guard controls supplement the actual native Astra API executions. */
#include "float-text-posix.h"
#include <assert.h>
#include <fenv.h>
#include <string.h>

int main(void) {
	unsigned char bytes[32], original[32];
	memset(bytes, 0xa5, sizeof bytes);
	memcpy(original, bytes, sizeof bytes);
	assert(astra_numeric_format_f64(1.0, bytes, 31) == -ASTRA_NUMERIC_OUTPUT);
	assert(astra_numeric_format_f32(1.0f, NULL, 32) == -ASTRA_NUMERIC_OUTPUT);
	assert(memcmp(bytes, original, sizeof bytes) == 0);
	struct astra_numeric_f64_cell wide = {42.0};
	struct astra_numeric_f32_cell narrow = {42.0f};
	assert(astra_numeric_parse_f64(NULL, 1, &wide) == ASTRA_NUMERIC_INVALID);
	assert(astra_numeric_parse_f64((const unsigned char *)"1", -1, &wide) == ASTRA_NUMERIC_INVALID);
	assert(astra_numeric_parse_f32((const unsigned char *)"1", 1, NULL) == ASTRA_NUMERIC_INVALID);
	const unsigned char invalid[] = {0xc0, 0xaf};
	assert(astra_numeric_parse_f64(invalid, 2, &wide) == ASTRA_NUMERIC_INVALID);
	assert(astra_numeric_parse_f32(invalid, 2, &narrow) == ASTRA_NUMERIC_INVALID);
	const unsigned char terminated[] = {'1', 0, '.', '5'};
	assert(astra_numeric_parse_f64(terminated, 4, &wide) == ASTRA_NUMERIC_INVALID);
	assert(astra_numeric_parse_f32((const unsigned char *)"1e100", 5, &narrow) == ASTRA_NUMERIC_OVERFLOW);
	assert(astra_numeric_parse_f64((const unsigned char *)"1e-99999", 8, &wide) == ASTRA_NUMERIC_UNDERFLOW);
	assert(wide.value == 42.0 && narrow.value == 42.0f);
	const int modes[] = {FE_DOWNWARD, FE_UPWARD, FE_TOWARDZERO};
	for (unsigned i = 0; i < sizeof modes / sizeof modes[0]; i++) {
		assert(fesetround(modes[i]) == 0);
		assert(astra_numeric_format_f64(1.0, bytes, 32) == -ASTRA_NUMERIC_ROUNDING);
		assert(astra_numeric_format_f32(1.0f, bytes, 32) == -ASTRA_NUMERIC_ROUNDING);
		assert(astra_numeric_parse_f64((const unsigned char *)"1", 1, &wide) == ASTRA_NUMERIC_ROUNDING);
		assert(astra_numeric_parse_f32((const unsigned char *)"1", 1, &narrow) == ASTRA_NUMERIC_ROUNDING);
		assert(fegetround() == modes[i]);
		assert(memcmp(bytes, original, sizeof bytes) == 0);
		assert(wide.value == 42.0 && narrow.value == 42.0f);
	}
	assert(fesetround(FE_TONEAREST) == 0);
	return 0;
}
