/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern int32_t record_query16_native_run(void);
extern uint32_t query16_retired_count(int32_t);

int main(void) {
	int32_t result = record_query16_native_run();
	if (result) {
		fprintf(stderr, "API B native result %d\n", result);
		return 1;
	}
	assert(query16_retired_count(1) == 1 && query16_retired_count(2) == 1 && query16_retired_count(3) == 4 && query16_retired_count(4) == 2);
	puts("PASS frozen API B native query algorithms and independent object lifetimes");
	return 0;
}
