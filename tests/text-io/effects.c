/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdint.h>
#include <unistd.h>

int32_t record(int32_t value) {
	unsigned char byte = (unsigned char)value;
	assert(write(2, &byte, 1) == 1);
	return value;
}

int32_t zero(void) {
	return 0;
}

int32_t ordered(int32_t a, const unsigned char *x, int32_t xn, int32_t b, const unsigned char *y, int32_t yn, int32_t c) {
	assert(a == 1 && b == 3 && c == 1 && xn == 4 && yn == 5 && x[0] == 'l' && y[0] == 'r');
	record(8);
	return 0;
}
