/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "context-provider.h"
#include <assert.h>
#include <stdio.h>

static unsigned retired;

void owning_record_item_retired(int identity) {
	assert(identity == 17 && retired++ == 0);
}

int owning_record_finish(void) {
	assert(retired == 1 && m17_custom_provider_retired() == 2);
	puts("owning generic records: nested move/result/context field, independent origins and exact Class/handle cleanup");
	return 0;
}
