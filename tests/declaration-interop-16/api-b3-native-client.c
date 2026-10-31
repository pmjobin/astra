/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern int32_t orbit16_native_run(void);
extern uint32_t orbit16_retired_count(int32_t);
int main(void) {
	int32_t result = orbit16_native_run();
	if (result) {
		fprintf(stderr, "API B3 native result %d\n", result);
		return 1;
	}
	assert(orbit16_retired_count(1) == 1 && orbit16_retired_count(2) == 1 && orbit16_retired_count(3) == 4 && orbit16_retired_count(4) == 2);
	puts("PASS frozen API B3 native query algorithms and independent object lifetimes");
	return 0;
}
