// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include "foreign-14.h"
#include <stdatomic.h>
#include <stdlib.h>

static atomic_uint_fast64_t next_identity = ATOMIC_VAR_INIT(1);
static _Thread_local uint64_t identity;

uint64_t astra_foreign14_thread_identity(void) {
	if (identity == 0) {
		uint_fast64_t next = atomic_fetch_add_explicit(&next_identity, 1, memory_order_relaxed);
		if (next == 0 || next >= UINT64_MAX) {
			abort();
		}
		identity = (uint64_t)next;
	}
	return identity;
}
