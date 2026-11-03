// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <windows.h>
#include <stdint.h>
#include "allocation-oracle.hpp"
static LONG constructed;
static LONG destroyed;
static LONG invalid;

extern "C" int32_t com14_created(int32_t value) {
	if (value != 40 && value != 9) InterlockedIncrement(&invalid);
	InterlockedIncrement(&constructed);
	return 0;
}

extern "C" int32_t com14_destroyed(int32_t value) {
	if (value != 40 && value != 17 && value != 9) InterlockedIncrement(&invalid);
	InterlockedIncrement(&destroyed);
	return 0;
}

extern "C" __declspec(dllexport) LONG com14_stats(LONG index) {
	return index == 0 ? constructed : index == 1 ? destroyed
	                              : index == 2   ? invalid
	                              : index == 3   ? static_cast<LONG>(allocation_live)
	                              : index == 4   ? static_cast<LONG>(allocation_total)
	                                             : static_cast<LONG>(allocation_retired);
}

extern "C" __declspec(dllexport) void com14_fail_after(uint32_t count) {
	allocation_fail_after = count;
}
