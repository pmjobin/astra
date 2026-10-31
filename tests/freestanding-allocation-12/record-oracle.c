/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "allocation-12.h"
#include <stdio.h>
extern AstraAlloc12Domain PART_DOMAIN, PARENT_DOMAIN;
void record_event(int32_t value) {
	printf("%d,", value);
}
int32_t record_probe(void) {
	putchar('\n');
	return PART_DOMAIN.live == 0 && PART_DOMAIN.allocations == 5 && PART_DOMAIN.releases == 5 &&
	       PARENT_DOMAIN.live == 0 && PARENT_DOMAIN.allocations == 2 && PARENT_DOMAIN.releases == 2;
}
