// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdio.h>

int checked_event(int kind, int id) {
	return printf("checked=%d:%d\n", kind, id) < 0 || fflush(stdout) != 0 ? -1 : 0;
}
