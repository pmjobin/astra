/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdio.h>
static unsigned step;
void manual_observed(int stage) {
	const int order[] = {2, 3, 1};
	assert(step < 3 && stage == order[step++]);
}
__attribute__((destructor)) static void verify(void) {
	assert(step == 3);
	puts("REAL generated host loop: ready wait and completion wait dispatch no user body; bounded pump resumes; run observes root");
}
