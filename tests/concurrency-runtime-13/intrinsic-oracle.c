// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
static int destroyed;

int32_t intrinsic_destroy(int32_t value) {
	assert(value == 17 && destroyed == 0);
	++destroyed;
	return 0;
}

int32_t intrinsic_finish(void) {
	assert(destroyed == 1);
	puts("intrinsic: one payload destruction, expired weak handle");
	return 0;
}
