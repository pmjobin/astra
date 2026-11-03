/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "gobject-signals-16.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern int32_t orbit16_roundtrip_run(void);
extern uint32_t orbit16_retired_count(int32_t);
static unsigned notes;

int32_t orbit16_roundtrip_note(int32_t value) {
	assert((notes == 0 && value == 1) || (notes == 1 && value == 2) || (notes == 2 && value == 102));
	++notes;
	return 0;
}

int main(void) {
	int32_t result = orbit16_roundtrip_run();
	if (result) {
		fprintf(stderr, "API B3 GIR result %d\n", result);
		return 1;
	}
	assert(notes == 3 && astra_gobject16_signal_connections() == 0 && orbit16_retired_count(1) == 1 && orbit16_retired_count(2) == 1 && orbit16_retired_count(3) == 2);
	puts("PASS frozen API B3 GIR native record queries, nullable objects and retained typed Closure");
	return 0;
}
