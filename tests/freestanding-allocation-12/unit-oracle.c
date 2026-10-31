/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "allocation-12.h"
#include <stdio.h>
extern AstraAlloc12Domain UNIT_DOMAIN;
void unit_event(int32_t value) {
	printf("%d,", value);
}
int32_t unit_probe(void) {
	AstraAlloc12Domain *d = &UNIT_DOMAIN;
	putchar('\n');
	return d->live == 0 && d->allocations == 3 && d->releases == 3 && d->peak_live == 3 &&
	       d->blocks[0].offset % 64 == 0 && d->blocks[1].offset % 64 == 0 && d->blocks[2].offset % 64 == 0;
}
