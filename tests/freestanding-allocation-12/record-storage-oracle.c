/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "allocation-12.h"
#include <stdio.h>
extern AstraAlloc12Domain NODE_DOMAIN, RECORD_DOMAIN;

void record_store_event(int32_t value) {
	printf("%d,", value);
}

int32_t record_store_probe(void) {
	AstraAlloc12Domain *n = &NODE_DOMAIN, *r = &RECORD_DOMAIN;
	putchar('\n');
	return n->live == 0 && n->allocations == 6 && n->releases == 6 && n->peak_live == 6 &&
	       r->live == 0 && r->allocations == 3 && r->releases == 3 && r->peak_live == 3 && r->peak_used == 144 && n->peak_used == 324;
}
