// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Independent TEST oracle only; never linked into astrac or an IR stage.
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <fenv.h>
#include <float.h>
#include <inttypes.h>
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
	_Static_assert(sizeof(float) == sizeof(uint32_t), "oracle requires binary32 float");
	_Static_assert(FLT_RADIX == 2 && FLT_MANT_DIG == 24 && FLT_MIN_EXP == -125 && FLT_MAX_EXP == 128, "oracle requires IEEE binary32");
	assert(setlocale(LC_ALL, "C") != NULL);
	assert(fesetround(FE_TONEAREST) == 0 && fegetround() == FE_TONEAREST);
	char *line = NULL;
	size_t capacity = 0;
	while (getline(&line, &capacity, stdin) >= 0) {
		char *end;
		float value = strtof(line, &end);
		assert(end != line && (*end == '\n' || *end == '\0'));
		uint32_t bits;
		memcpy(&bits, &value, sizeof(bits));
		printf("%08" PRIx32 "\n", bits);
	}
	free(line);
	return 0;
}
