// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdint.h>
#include <stdio.h>

int32_t callable_event(int32_t stage, int32_t tag) {
	printf("%d:%d\n", stage, tag);
	return 0;
}
