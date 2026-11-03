// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
static int retired, seen;

int32_t captured16_retired(void) {
	return ++retired;
}

void captured16_seen(int32_t value) {
	assert(value == 21 && retired == 0);
	++seen;
}

extern int32_t captured16_run(void);

int main(void) {
	assert(captured16_run() == 0 && retired == 3 && seen == 1);
	puts("PASS captured scalar/BOOL/void callbacks and exact environment retirement");
	return 0;
}
