// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdint.h>
#include <stdio.h>
#include <string.h>

int mark(int x) {
	putchar('0' + x);
	fflush(stdout);
	return x;
}

int bits32(float x) {
	int32_t bits;
	memcpy(&bits, &x, sizeof bits);
	return bits;
}

int high64(double x) {
	uint64_t bits;
	memcpy(&bits, &x, sizeof bits);
	uint32_t word = (uint32_t)(bits >> 32);
	int32_t result;
	memcpy(&result, &word, sizeof result);
	return result;
}

int low64(double x) {
	uint64_t bits;
	memcpy(&bits, &x, sizeof bits);
	uint32_t word = (uint32_t)bits;
	int32_t result;
	memcpy(&result, &word, sizeof result);
	return result;
}
