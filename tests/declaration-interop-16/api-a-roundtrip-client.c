/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "gobject-signals-16.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern int32_t byte16_roundtrip_run(void);
extern uint32_t byte16_retired_count(int32_t);
static unsigned notes;

int32_t byte16_roundtrip_note(int32_t value) {
	assert((notes == 0 && value == 1) || (notes == 1 && value == 101));
	++notes;
	return 0;
}

int main(void) {
	int32_t result = byte16_roundtrip_run();
	if (result) {
		fprintf(stderr, "API A GIR result %d\n", result);
		return 1;
	}
	assert(notes == 2 && astra_gobject16_signal_connections() == 0 && byte16_retired_count(1) == 1 && byte16_retired_count(3) == 1 && byte16_retired_count(4) == 1);
	puts("PASS API A GIR imported native algorithms, owned channels and retained typed Closure");
	return 0;
}
