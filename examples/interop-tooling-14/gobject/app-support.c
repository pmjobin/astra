/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdlib.h>
#define APP_SUPPORT(app) \
	static int32_t app##_counts[6]; \
	int32_t app##_created(int32_t value) { (void)value; ++app##_counts[0]; return 0; } \
	int32_t app##_closed(int32_t value, int32_t revisions) { ++app##_counts[1]; app##_counts[2] = value; app##_counts[3] = revisions; return 0; } \
	int32_t app##_stats(int32_t index) { return index >= 0 && index < 6 ? app##_counts[index] : -1; }
APP_SUPPORT(a126)
APP_SUPPORT(a127)
APP_SUPPORT(a128)
int32_t a127_text_event(int32_t delta) {
	a127_counts[4] += delta;
	if (delta == 1) ++a127_counts[5];
	if (a127_counts[4] < 0 || a127_counts[4] > 1) abort();
	return 0;
}
