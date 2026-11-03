/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <assert.h>
static unsigned observed, retired;

void callables16_observe(int32_t value, double scale) {
	const int32_t values[] = {7, 9, 15, 16, 21, 32};
	const double scales[] = {2.5, 6.5, 3.5, 3.5, 4.5, 5.5};
	assert(observed < 6 && value == values[observed] && scale == scales[observed]);
	++observed;
}

void callables16_retire(void) {
	++retired;
}

extern int32_t native_callables16_run(void);

int main(void) {
	assert(native_callables16_run() == 0);
	assert(observed == 6 && retired == 3);
	puts("PASS native void Fn and checked/ordinary closure effects");
	return 0;
}
