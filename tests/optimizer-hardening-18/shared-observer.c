// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdio.h>
void shared18_retire(int value) {
	printf("retire=%d\n", value);
}
void shared18_observe(int value) {
	printf("observe=%d\n", value);
}
