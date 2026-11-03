/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
extern int64_t surge4_event_checksum(int32_t, int32_t, int32_t);

int main(void) {
	for (int mode = 0; mode < 2; ++mode) {
		for (int first = -17; first <= 17; ++first) {
			for (int count = 0; count <= 19; ++count) {
				int64_t expected = 0;
				for (int index = 0; index < count; ++index)
					expected += mode ? first + index + 3 : 2 * (first + index);
				if (surge4_event_checksum(first, count, mode) != expected) return 1;
			}
		}
	}
	if (surge4_event_checksum(0, -1, 0) != -99999999) return 2;
	puts("event-client: 1400 callback sequences verified");
	return 0;
}
