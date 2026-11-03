/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
static unsigned retired[5], seen[2];

void heap_choice_retired(int32_t identity) {
	if (identity < 1 || identity > 4 || retired[identity]++) abort();
}

void heap_choice_observed(int32_t mode, int32_t value) {
	if (mode < 0 || mode > 1 || seen[mode]++) abort();
	int selected = mode == 0 ? 1 : 4;
	int discarded = mode == 0 ? 2 : 3;
	if (value != (mode == 0 ? 17 : 29) || retired[selected] || retired[discarded] != 1) abort();
}

int32_t heap_choice_finish(void) {
	if (seen[0] != 1 || seen[1] != 1) abort();
	for (int i = 1; i <= 4; ++i)
		if (retired[i] != 1) abort();
	puts("heap choices: selected catch origin retained, other input retired, four exact destructions");
	return 0;
}

int32_t heap_choice_probe(void);

int main(void) {
	return heap_choice_probe();
}
