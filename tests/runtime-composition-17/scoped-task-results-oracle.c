/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#ifndef SCOPED_RESULT_EMPTY
#define SCOPED_RESULT_EMPTY 0
#endif
#ifndef SCOPED_RESULT_SINGLE
#define SCOPED_RESULT_SINGLE 0
#endif
static unsigned seen[17], observations, ready;

void scoped_result_ready(int32_t mode) {
	if (mode == 4 && ready++) abort();
}

int32_t scoped_result_is_ready(void) {
	return (int32_t)ready;
}

void scoped_result_retired(int32_t identity) {
	if (identity < 1 || identity > 16 || seen[identity]++) abort();
}

void scoped_result_observed(int32_t first, int32_t second, int32_t marker) {
	if (marker != 17) abort();
	if (observations == 0) {
		if (SCOPED_RESULT_EMPTY) {
			if (first != 0 || second != 0 || seen[1] != 1 || seen[2] != (SCOPED_RESULT_SINGLE ? 0U : 1U)) abort();
		} else if (first != 1 || second != 2 || seen[1] || seen[2])
			abort();
	} else if (observations == 1) {
		if (first != 0 || second != 0 || seen[13] != 1 || seen[14] != (SCOPED_RESULT_SINGLE ? 0U : 1U)) abort();
	} else if (observations == 2) {
		if (first != 0 || second != 0 || seen[15] != 1 || seen[16] != (SCOPED_RESULT_SINGLE ? 0U : 1U)) abort();
	} else
		abort();
	observations++;
}

int32_t scoped_result_finish(void) {
	for (unsigned i = 1; i <= 16; i++)
		if (seen[i] != 1) abort();
	if (observations != 3 || ready != 1) abort();
	puts("scoped results: exact observed owners, error, cancellation and cold discard");
	return 0;
}

int32_t scoped_result_probe(void);

int main(void) {
	return scoped_result_probe();
}
