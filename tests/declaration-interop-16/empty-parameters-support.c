/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
static uint32_t retired;
int32_t empty16_retired(void) {
	++retired;
	return 0;
}
uint32_t empty16_retired_count(void) {
	return retired;
}
