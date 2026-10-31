/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static int kind;
static unsigned retired[3];
#ifdef M17_SCOPED_RECORD
enum { expected = 2 };
#else
enum { expected = 1 };
#endif
void checked_scope_begin(int32_t value) {
	if (value < 1 || value > 2) abort();
	for (unsigned identity = 1; identity <= expected; identity++) {
		if (kind && retired[identity] != 1) abort();
		retired[identity] = 0;
	}
	kind = value;
}
void checked_scope_retired(int32_t identity) {
	if (!kind || identity < 1 || identity > expected || retired[identity]++) abort();
}
int32_t checked_scope_finish(void) {
	for (unsigned identity = 1; identity <= expected; identity++)
		if (retired[identity] != 1) abort();
	puts(kind == 1 ? "checked scoped region: refused capture preserved, admitted capture moved, original owner retired once" : "checked scoped pool: refused capture preserved, admitted capture moved, original owner retired once");
	return 0;
}
extern int32_t checked_scope_run(int32_t kind);
int main(void) {
	for (int32_t profile = 1; profile <= 2; profile++) {
		int32_t result = checked_scope_run(profile);
		if (result) return result;
	}
	return 0;
}
