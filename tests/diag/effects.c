/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdint.h>
#include <unistd.h>

int32_t diag_mark(int32_t event) {
	unsigned char byte = (unsigned char)event;
	assert(write(1, &byte, 1) == 1);
	return event;
}

int32_t diag_zero(void) {
	return 0;
}
