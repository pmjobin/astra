// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdio.h>

void state_event(int kind, int tag) {
	printf("event %d %d\n", kind, tag);
	fflush(stdout);
}
