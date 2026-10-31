/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdio.h>
static int lengths, capacities, reserves, inspections;
void observe(int kind, int value, int bound) {
	if (kind == 0) {
		assert(value == ++lengths && bound == 0);
	} else if (kind == 1) {
		assert(++capacities == lengths && bound == lengths);
		assert(value == (lengths == 1 ? 3 : 5));
	} else {
		assert(kind == 2 && ++inspections == lengths && bound == 0);
		assert(value == (lengths == 1 ? 17 : 23));
	}
}
void observed_reserve(int result) {
	assert(result == 1 && ++reserves == lengths);
}
int slots_finish(void) {
	assert(lengths == 2 && capacities == 2 && reserves == 2 && inspections == 2);
	puts("generic owner slots: copied length/capacity/reserve retain scalar call roles and exact backing retirement");
	return 0;
}
