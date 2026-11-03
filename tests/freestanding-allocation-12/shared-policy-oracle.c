/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "allocation-12.h"
#include <stdio.h>
extern AstraAlloc12Domain SHARED_DOMAIN;

void shared_policy_event(int32_t value) {
	printf("%d,", value);
}

int32_t shared_policy_probe(int32_t phase) {
	AstraAlloc12Domain *d = &SHARED_DOMAIN;
	if (phase == 1) {
		return d->live == 1 && d->allocations == 1 && d->releases == 0;
	}
	if (phase == 2) {
		return d->live == 0 && d->allocations == 1 && d->releases == 1;
	}
	if (phase == 3) {
		putchar('\n');
		return d->live == 0 && d->allocations == 2 && d->releases == 2 && d->peak_live == 1;
	}
	return 0;
}
