// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <windows.h>
#include <stdint.h>
static LONG created, destroyed, invalid;

extern "C" int32_t a125_constructed(int32_t capacity) {
	++created;
	if (capacity != 60) ++invalid;
	return 0;
}

extern "C" int32_t a125_closed(int32_t capacity, int32_t spent) {
	++destroyed;
	if (capacity != 60 || spent != 60) ++invalid;
	return 0;
}

extern "C" __declspec(dllexport) LONG a125_stats(LONG index) {
	return index == 0 ? created : index == 1 ? destroyed
	                                         : invalid;
}
