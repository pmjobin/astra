/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdio.h>
#include "context-provider.h"
static unsigned born, retired;

void context_owner_event(int value) {
	unsigned bit;
	switch (value < 0 ? -value : value) {
	case 11:
		bit = 1;
		break;
	case 17:
		bit = 2;
		break;
	case 23:
		bit = 4;
		break;
	case 31:
		bit = 8;
		break;
	case 37:
		bit = 16;
		break;
	default:
		assert(0);
		return;
	}
	if (value > 0) {
		assert(!(born & bit));
		born |= bit;
	} else {
		assert((born & bit) && !(retired & bit));
		retired |= bit;
	}
}

int context_owner_finish(void) {
	assert(born == 31 && retired == 31 && m17_custom_provider_retired() == 1);
	puts("context owners: two runtime instances, borrowed factory, escaping backing, external custom provider, exact five destructors");
	return 0;
}
