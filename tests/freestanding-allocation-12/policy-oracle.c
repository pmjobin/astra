/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "allocation-12.h"
#include <stdio.h>

extern AstraAlloc12Domain CUSTOM_DOMAIN, HEAP_DOMAIN, STATIC_DOMAIN;
static int last_destructor;
static int valid = 1;

void policy_event(int32_t stage, int32_t value) {
	printf("%d:%d,", stage, value);
	if (stage == 11) {
		last_destructor = value;
	}
	if (stage == 2 && last_destructor != (value == 256 ? 8 : 7)) {
		valid = 0;
	}
	if (stage == 99) {
		valid = 0;
	}
}

int32_t policy_probe(int32_t phase) {
	AstraAlloc12Domain *c = &CUSTOM_DOMAIN, *h = &HEAP_DOMAIN, *s = &STATIC_DOMAIN;
	if (!valid) {
		return 0;
	}
	if (phase == 1) {
		/* Independent observer of the runtime's documented private heap node. */
		struct Node {
			void *next, *payload;
			uint64_t bytes, generation, tag;
		};
		struct Node *node = h->heap_head;
		return c->live == 2 && c->blocks[0].offset == 0 && c->blocks[1].offset == 256 &&
		       h->live == 1 && h->allocations == 1 && node && node->bytes == 4 &&
		       (uintptr_t)node->payload % 128 == 0 && s->live == 1 && s->allocations == 1 &&
		       s->error == ASTRA_ALLOC12_EXHAUSTED;
	}
	if (phase == 2) {
		putchar('\n');
		return c->live == 0 && c->allocations == 2 && c->releases == 2 && h->live == 0 &&
		       h->allocations == 1 && h->releases == 1 && !h->heap_head && s->live == 0 &&
		       s->allocations == 2 && s->releases == 2 && c->peak_used == 260 && h->peak_used == 4 && s->peak_used == 4;
	}
	return 0;
}
