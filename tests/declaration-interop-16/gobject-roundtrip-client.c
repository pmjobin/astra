// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern int32_t roundtrip_main(void);
extern int32_t go16_destroyed_count(void);
extern int32_t go16_item_destroyed_count(void);
static int called;

void roundtrip_sink(double value) {
	assert(value == 1.25);
	++called;
}

int main(void) {
	int result = roundtrip_main();
	if (result) {
		fprintf(stderr, "roundtrip result=%d\n", result);
		return result;
	}
	assert(called == 1);
	assert(go16_destroyed_count() == 1);
	assert(go16_item_destroyed_count() == 2);
	puts("PASS native GIR roundtrip ownership and algorithms");
	return 0;
}
