/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <assert.h>
#include <stdio.h>
static unsigned calls;
void callback_views16_seen(int32_t value) {
	assert(value == 19);
	++calls;
}
extern int32_t callback_views16_run(void);
int main(void) {
	assert(callback_views16_run() == 0 && calls == 1);
	puts("PASS distinct native callback code/context views");
	return 0;
}
