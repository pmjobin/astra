// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern int32_t opaque_gir_run(void);
extern unsigned gobjectunit16_retired_count(void);

int main(void) {
	assert(opaque_gir_run() == 0 && gobjectunit16_retired_count() == 1);
	puts("PASS opaque SDK GIR imported native algorithms and exact retirement");
	return 0;
}
