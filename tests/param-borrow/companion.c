// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include "../buffer/companion.c"
int32_t pb_touch(void *pointer) {
	int id = bb_id(pointer);
	return ++resources[id].id;
}
int32_t pb_value(void *pointer) {
	int id = bb_id(pointer);
	return resources[id].id;
}
