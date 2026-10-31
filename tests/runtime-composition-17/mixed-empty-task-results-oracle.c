/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
static unsigned retired[3], observed;
void mixed_result_retired(int32_t identity) {
	if (identity < 1 || identity > 2 || retired[identity]++) abort();
}
void mixed_result_observed(void) {
	if (observed++ || retired[1] != 1 || retired[2] != 0) abort();
}
int32_t mixed_result_finish(void) {
	if (observed != 1 || retired[1] != 1 || retired[2] != 1) abort();
	puts("mixed result: empty field retires its input, retained field keeps its exact owner");
	return 0;
}
int32_t mixed_result_probe(void);
int main(void) {
	return mixed_result_probe();
}
