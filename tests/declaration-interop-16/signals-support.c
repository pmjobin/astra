// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdint.h>
static unsigned retired;
static unsigned item_retired;

int32_t signals16_retired(void) {
	++retired;
	return 0;
}

unsigned signals16_retired_count(void) {
	return retired;
}

int32_t signals16_item_retired(void) {
	++item_retired;
	return 0;
}

unsigned signals16_item_retired_count(void) {
	return item_retired;
}
