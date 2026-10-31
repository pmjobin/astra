/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdio.h>

static unsigned retired[31];
static unsigned faults[3][3];
static int invalid;

void record_creation_fault(int mode, int first, int event) {
	if (mode < 1 || mode > 2 || event < 1 || event > 2 ||
	    first < 1 || first >= 30) {
		invalid = 1;
		return;
	}
	if (first != (mode == 1 ? 7 : 13) &&
	    first != (mode == 1 ? 9 : 15) &&
	    first != (mode == 1 ? 11 : 17)) invalid = 1;
	if (retired[first] != (unsigned)(event - 1) ||
	    retired[first + 1] != (unsigned)(event - 1)) invalid = 1;
	faults[mode][event]++;
}

void record_creation_retired(int identity) {
	if (identity < 1 || identity > 30) {
		invalid = 1;
		return;
	}
	retired[identity]++;
}

int record_creation_finish(void) {
	if (invalid) return 1;
	for (int i = 1; i <= 30; i++) {
		if (retired[i] != 1) return 2;
	}
	for (int mode = 1; mode <= 2; mode++) {
		if (faults[mode][1] != 3 || faults[mode][2] != 3) return 3;
	}
	puts("record creation: promoted flat/nested/generic fields, checked factories and local moves, scoped context calls, 6 observed exceptions and 30 exact retirements");
	return 0;
}
