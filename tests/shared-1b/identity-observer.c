// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdint.h>
#include <stdlib.h>
static int32_t drops;

void identity_drop(int32_t value) {
	if (value != 7) {
		abort();
	}
	drops++;
}

int32_t identity_drops(void) {
	return drops;
}
