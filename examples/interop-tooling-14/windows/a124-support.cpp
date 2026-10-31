// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <windows.h>
#include <stdint.h>
static LONG created, destroyed, invalid;
extern "C" int32_t a124_constructed(int32_t temperature) {
	++created;
	if (temperature != 30) ++invalid;
	return 0;
}
extern "C" int32_t a124_closed(int32_t temperature, int32_t adjustments) {
	++destroyed;
	if (temperature != 10 || adjustments != 3) ++invalid;
	return 0;
}
extern "C" __declspec(dllexport) LONG a124_stats(LONG index) {
	return index == 0 ? created : index == 1 ? destroyed
	                                         : invalid;
}
