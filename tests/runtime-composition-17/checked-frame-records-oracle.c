/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "../../lib/runtime/runtime/context-17.h"
#include <assert.h>
#include <stdatomic.h>
static AstraContext17 *tokens[4];
static _Atomic int closed[4];

void checked_record_token(AstraContext17 *token, int identity) {
	assert(token && identity >= 1 && identity <= 4);
	int index = identity - 1;
	AstraContext17Snapshot state;
	assert(astra_context17_snapshot(token, &state) == 0 && state.live == 0);
	assert(!tokens[index]);
	tokens[index] = token;
}

void __real_astra_context17_destroy(AstraContext17 *);

void __wrap_astra_context17_destroy(AstraContext17 *context) {
	for (int i = 3; i >= 0; --i) {
		if (!context || context != tokens[i] || atomic_load(&closed[i])) {
			continue;
		}
		assert(atomic_fetch_add(&closed[i], 1) == 0);
		break;
	}
	__real_astra_context17_destroy(context);
}

int __real_checked_frame_finish(void);

int __wrap_checked_frame_finish(void) {
	for (int i = 0; i < 4; ++i) {
		assert(tokens[i] && atomic_load(&closed[i]) == 1);
	}
	return __real_checked_frame_finish();
}
