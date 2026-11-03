/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdio.h>
static unsigned retired;

void context_unit_retired(int value) {
	unsigned bit = value == 17 ? 1 : value == 23 ? 2
	                             : value == 31   ? 4
	                             : value == 47   ? 8
	                                             : 0;
	assert(bit && !(retired & bit));
	retired |= bit;
}

int context_unit_finish(void) {
	assert(retired == 15);
	puts("context native SDK: opaque leaf/middle, four exact origins and escaping backing");
	return 0;
}
