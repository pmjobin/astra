/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>

int32_t module_event(int32_t stage, int32_t value) {
	printf("%d:%d\n", stage, value);
	return 0;
}
