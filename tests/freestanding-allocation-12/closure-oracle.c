/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "allocation-12.h"
#include <stdio.h>
#include <stdlib.h>

extern AstraAlloc12Domain CLOSURE_DOMAIN;
static int registered, valid = 1;

static void finish(void) {
	AstraAlloc12Domain *d = &CLOSURE_DOMAIN;
	putchar('\n');
	if (!valid || d->live || d->allocations != 6 || d->releases != 6 || d->peak_live != 4 || d->peak_used != 232) {
		_Exit(93);
	}
}

void closure_event(int32_t stage, int32_t value) {
	if (!registered) {
		if (atexit(finish)) {
			_Exit(94);
		}
		registered = 1;
	}
	printf("%d:%d,", stage, value);
	/* Environment destruction must happen while its storage is still live. */
	if (stage == 3 && (CLOSURE_DOMAIN.live < 2 || CLOSURE_DOMAIN.live % 2)) {
		valid = 0;
	}
}

int32_t closure_probe(int32_t phase) {
	AstraAlloc12Domain *d = &CLOSURE_DOMAIN;
	if (phase == 1) {
		return d->live == 4 && d->allocations == 4 && d->releases == 0 && astra_alloc12_reset(d) == 0 && d->error == ASTRA_ALLOC12_LIVE;
	}
	if (phase == 2) {
		return d->live == 2 && d->releases == 2;
	}
	if (phase == 3) {
		return d->live == 0 && d->releases == 4 && astra_alloc12_reset(d) == 1;
	}
	return 0;
}
