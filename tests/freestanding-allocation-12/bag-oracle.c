/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "allocation-12.h"
#include <stdio.h>
extern AstraAlloc12Domain BAG_DOMAIN, DIAGNOSTIC_DOMAIN;

void bag_event(int32_t value) {
	printf("%d,", value);
}

int32_t bag_probe(int32_t phase) {
	AstraAlloc12Domain *d = &BAG_DOMAIN;
	if (phase == 1) {
		return d->live == 4 && d->allocations == 6 && d->releases == 2 && d->error == ASTRA_ALLOC12_EXHAUSTED;
	}
	if (phase == 2) {
		putchar('\n');
		return d->live == 0 && d->allocations == 6 && d->releases == 6 && d->peak_live == 5 && d->peak_used == 104 && DIAGNOSTIC_DOMAIN.live == 0 && DIAGNOSTIC_DOMAIN.allocations == 4 && DIAGNOSTIC_DOMAIN.releases == 4 && DIAGNOSTIC_DOMAIN.peak_live == 4;
	}
	return 0;
}
