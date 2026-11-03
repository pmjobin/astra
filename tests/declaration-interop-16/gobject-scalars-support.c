// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdint.h>
static int32_t destroyed;

int32_t go16_retired(void) {
	++destroyed;
	return 0;
}

int32_t go16_destroyed_count(void) {
	return destroyed;
}

static int32_t item_retirements;

int32_t go16_item_retired(void) {
	return ++item_retirements;
}

int32_t go16_item_destroyed_count(void) {
	return item_retirements;
}
