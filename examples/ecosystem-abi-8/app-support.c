/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
static int32_t created;
static int32_t destroyed;
static int32_t last;
int32_t app_lifetime(int32_t stage, int32_t value) {
	if (stage == 1) {
		created++;
	}
	if (stage == 9) {
		destroyed++;
		last = value;
	}
	return 0;
}
int32_t app_created(void) {
	return created;
}
int32_t app_destroyed(void) {
	return destroyed;
}
int32_t app_last_destroyed(void) {
	return last;
}
