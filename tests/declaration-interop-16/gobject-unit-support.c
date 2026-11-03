// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdint.h>
static unsigned retired;

int32_t gobjectunit16_retired(void) {
	++retired;
	return 0;
}

unsigned gobjectunit16_retired_count(void) {
	return retired;
}
