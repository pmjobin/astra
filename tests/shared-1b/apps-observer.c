/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdio.h>

int shared_app_event(int stage, int value) {
	return printf("%d:%d\n", stage, value) < 0;
}
