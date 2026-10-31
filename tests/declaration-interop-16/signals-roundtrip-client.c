/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "gobject-signals-16.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern int32_t signal_roundtrip_run(void);
extern unsigned signals16_retired_count(void);
static int32_t notes[4];
static unsigned count;
int32_t signal_roundtrip_note(int32_t value) {
	assert(count < 4);
	notes[count++] = value;
	return 0;
}
int main(void) {
	assert(signal_roundtrip_run() == 0 && count == 2 && notes[0] == 19 && notes[1] == 101 && signals16_retired_count() == 1 && astra_gobject16_signal_connections() == 0);
	puts("PASS scanned SDK signal round-trip through native imported methods and retained typed void Closure");
	return 0;
}
