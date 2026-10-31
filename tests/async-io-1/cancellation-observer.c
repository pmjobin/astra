/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdio.h>
static unsigned counts[5];
void cancelled_observed(int stage) {
	assert(stage >= 1 && stage <= 4 && counts[stage]++ == 0);
}
__attribute__((destructor)) static void verify(void) {
	assert(counts[1] == 1 && counts[2] == 1 && counts[3] == 1 && counts[4] == 1);
	puts("real generated cancellation: parent-only submitted subtree drain, unrelated progress, cold discard and immutable published success/exception discard");
}
