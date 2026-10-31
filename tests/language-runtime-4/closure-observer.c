// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdio.h>
int closure_app_event(int stage, int value) {
	int result = printf("event=%d:%d\n", stage, value);
	return result < 0 || fflush(stdout) != 0 ? -1 : 0;
}
