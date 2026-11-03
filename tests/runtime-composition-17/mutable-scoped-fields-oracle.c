/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
static unsigned retired[4], phase;

void mutable_retired(int32_t identity) {
	if (identity < 1 || identity > 3 || retired[identity]++) abort();
}

int32_t mutable_check(int32_t actual) {
	if (actual < 1 || actual > 3 || (unsigned)actual != ++phase) abort();
	for (int i = 1; i <= 3; ++i)
		if (retired[i] != (unsigned)(i <= actual)) abort();
	return 0;
}

int32_t mutable_probe(void);

int main(void) {
	int32_t result = mutable_probe();
	if (result != 0 || phase != 3) abort();
	puts("scoped mutation: old generations retire once and replacements retain their exact contexts");
	return 0;
}
