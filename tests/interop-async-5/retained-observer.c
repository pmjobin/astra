/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>

int32_t retained_app_event(int32_t stage, int32_t value) {
	printf("event=%d:%d\n", stage, value);
	return fflush(stdout) == 0 ? 0 : -1;
}
