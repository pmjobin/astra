/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern int32_t byte_service16_native_run(void);
extern uint32_t byte16_retired_count(int32_t);
int main(void) {
	int32_t result = byte_service16_native_run();
	if (result) {
		fprintf(stderr, "API A native result %d\n", result);
		return 1;
	}
	assert(byte16_retired_count(1) == 1 && byte16_retired_count(2) == 2 && byte16_retired_count(3) == 1 && byte16_retired_count(4) == 1);
	puts("PASS API A native leaf/component ownership, checked rollback and closed statistics");
	return 0;
}
