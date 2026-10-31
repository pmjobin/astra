/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "gobject-signals-16.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern int32_t empty16_run(void);
extern uint32_t empty16_retired_count(void);
static unsigned notes;
int32_t empty16_note(int32_t value) {
	assert((notes == 0 && value == 1) || (notes == 1 && value == 101));
	++notes;
	return 0;
}
int main(void) {
	assert(empty16_run() == 0 && notes == 2 && empty16_retired_count() == 1 && astra_gobject16_signal_connections() == 0);
	puts("PASS zero-argument GIR constructor and retained signal closure");
	return 0;
}
