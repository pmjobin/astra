/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned retired[6];
void scoped_task_retired(int32_t identity) {
	if (identity < 1 || identity > 5 || retired[identity]++) abort();
}
int32_t scoped_task_finish(void) {
	for (unsigned identity = 1; identity <= 5; identity++)
		if (retired[identity] != 1) abort();
	puts("scoped task captures: cold drop, delayed run, child handoff, error and cancellation retire original owners once");
	return 0;
}
extern int32_t scoped_task_captures_run(void);
int main(void) {
	return scoped_task_captures_run();
}
