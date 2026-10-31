// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
static unsigned sessions, facades;
int32_t opaque16_retired(void) {
	++sessions;
	return 0;
}
int32_t opaque16_facade_retired(void) {
	++facades;
	return 0;
}
extern int32_t opaque16_consumer(void);
int main(void) {
	assert(opaque16_consumer() == 0 && sessions == 2 && facades == 1);
	puts("PASS native-only opaque foreign declarations keep unique lifetimes");
	return 0;
}
