/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
typedef struct {
	int32_t category;
	int64_t count;
	double total;
} Report131;
_Static_assert(sizeof(Report131) == 24 && offsetof(Report131, count) == 8 && offsetof(Report131, total) == 16, "independent C aggregate layout");
static int observations[6], created[16], closed[16], bad;
int32_t a131_record(Report131 *record, int32_t stage) {
	if (!record || stage != 0 || record->category != 7 || record->count != 11 || record->total != 3.5) ++bad;
	++observations[0];
	return 42;
}
int32_t a131_integer(int32_t *value, int32_t stage) {
	if (!value || *value != 42 || stage != 4) ++bad;
	++observations[4];
	return value ? *value : -1;
}
int32_t a131_marker(int32_t stage, int32_t value) {
	if (stage < 1 || stage > 5) abort();
	const int expected[] = {0, 35, 27, 19, 0, 7};
	if (value != expected[stage]) ++bad;
	++observations[stage];
	return value;
}
int32_t a131_event(int32_t stage, int32_t identity, int32_t value) {
	if (identity != 7 && identity != 9 && identity != 11) abort();
	if (stage == 1) {
		++created[identity];
		if (value != 0) ++bad;
	} else {
		if (stage != 0 || value != 1) ++bad;
		++closed[identity];
	}
	return 0;
}
int32_t a131_mode(void) {
	const char *mode = getenv("A131_FAIL");
	return mode ? atoi(mode) : 0;
}
int32_t a131_finish(void) {
	for (int i = 0; i < 5; ++i)
		if (observations[i] != 1) ++bad;
	if (observations[5] != (a131_mode() != 0)) ++bad;
	for (int i = 7; i <= 11; i += 2)
		if (created[i] != 1 || closed[i] != 1) ++bad;
	if (bad) {
		fprintf(stderr, "FAIL A131 lifecycle/oracle errors=%d\n", bad);
		return 90;
	}
	puts("PASS A131: aggregate module closure async checked-exception foreign-stacks three-exact-destructions");
	return 0;
}
