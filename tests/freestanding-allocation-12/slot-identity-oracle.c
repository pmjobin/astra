/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "allocation-12.h"
extern AstraAlloc12Domain SLOT_DOMAIN;

int32_t slot_identity_probe(void) {
	AstraAlloc12Domain *d = &SLOT_DOMAIN;
	uint64_t tags[4] = {LEFT_OBJECT, RIGHT_OBJECT, LEFT_SLOTS, RIGHT_SLOTS};
	if (d->live != 4 || d->allocations != 4 || d->releases) {
		return 0;
	}
	for (unsigned i = 0; i < 4; ++i) {
		if (!d->blocks[i].live || d->blocks[i].tag != tags[i] || d->blocks[i].bytes != 16) {
			return 0;
		}
	}
	return 1;
}
