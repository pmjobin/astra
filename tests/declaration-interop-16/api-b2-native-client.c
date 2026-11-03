/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern int32_t catalog16_native_run(void);
extern uint32_t lens16_retired_count(int32_t);

int main(void) {
	int32_t result = catalog16_native_run();
	if (result) {
		fprintf(stderr, "API B2 native result %d\n", result);
		return 1;
	}
	assert(lens16_retired_count(1) == 1 && lens16_retired_count(2) == 1 && lens16_retired_count(3) == 4 && lens16_retired_count(4) == 2);
	puts("PASS frozen API B2 native query algorithms and independent object lifetimes");
	return 0;
}
