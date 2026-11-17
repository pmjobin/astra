/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdio.h>

static int count;
static int total;

void note_drop(int value) {
	count++;
	total += value;
}

int drop_count(void) {
	return count;
}

int drop_sum(void) {
	printf("Astra C ABI: %d drops, sum %d\n",count,total);
	return total;
}
