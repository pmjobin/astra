/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "allocation-12.h"
#include <stdio.h>

extern AstraAlloc12Domain POOL_DOMAIN;
static uint64_t retired_generation, tag;
static void *retired;

void pool_event(int32_t value) {
	printf("%d,", value);
}

int32_t pool_probe(int32_t phase) {
	AstraAlloc12Domain *d = &POOL_DOMAIN;
	if (phase == 1) {
		retired = d->backing + d->blocks[0].offset;
		retired_generation = d->blocks[0].generation;
		tag = d->blocks[0].tag;
		AstraAlloc12Domain other = {0};
		if (d->error != ASTRA_ALLOC12_EXHAUSTED || d->live != 2 || d->allocations != 2 || d->releases) {
			return 0;
		}
		if (astra_alloc12_release(&other, retired, tag, retired_generation) != 0 ||
		    astra_alloc12_release(d, retired, tag ^ 1, retired_generation) != 0 || d->live != 2) {
			return 0;
		}
		return d->error == ASTRA_ALLOC12_ORIGIN;
	}
	if (phase == 2) {
		if (d->live != 2 || d->allocations != 3 || d->releases != 1 || d->blocks[0].generation <= retired_generation || d->backing + d->blocks[0].offset != retired) {
			return 0;
		}
		return astra_alloc12_release(d, retired, tag, retired_generation) == 0 && d->error == ASTRA_ALLOC12_GENERATION && d->live == 2;
	}
	if (phase == 3) {
		putchar('\n');
		return d->live == 0 && d->allocations == 19 && d->releases == 19 && d->peak_live == 2 && d->peak_used == 68 && astra_alloc12_reset(d) == 1;
	}
	return 0;
}
