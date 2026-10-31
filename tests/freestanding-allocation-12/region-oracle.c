/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "allocation-12.h"
#include <stdio.h>

extern AstraAlloc12Domain REGION_DOMAIN;

void owner_event(int32_t value) {
	printf("%d,", value);
}

int32_t region_probe(int32_t phase) {
	AstraAlloc12Domain *d = &REGION_DOMAIN;
	if (d->kind != ASTRA_ALLOC12_REGION || d->capacity != 4096 ||
	    d->block_capacity != 64 || (uintptr_t)d->backing % 4096) {
		return 0;
	}
	if (phase == 1) {
		if (d->live != 3 || d->allocations != 3 || d->releases ||
		    d->blocks[0].bytes != 4 || d->blocks[1].bytes != 12 ||
		    d->blocks[2].bytes != 4 || d->blocks[0].offset % 64 ||
		    d->blocks[2].offset % 64) {
			return 0;
		}
		return astra_alloc12_reset(d) == 0 && d->error == ASTRA_ALLOC12_LIVE && d->live == 3;
	}
	if (phase == 2) {
		return d->live == 0 && d->used == 0 && d->allocations == 27 && d->releases == 27 && astra_alloc12_reset(d) == 1;
	}
	if (phase == 3) {
		return d->live == 1 && d->allocations == 28 && d->releases == 27 && d->blocks[0].offset == 0;
	}
	if (phase == 4) {
		putchar('\n');
		return d->live == 0 && d->used == 0 && d->allocations == 28 && d->releases == 28 && d->peak_live == 5 && d->peak_used == 848;
	}
	return 0;
}
