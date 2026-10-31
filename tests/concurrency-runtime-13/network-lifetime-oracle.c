// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include "../../lib/runtime/async/virtual.h"
#include <assert.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
static _Atomic int observed[6];
static _Thread_local int finishing;
int32_t net_oracle_lifetimes(int32_t expected);
void __real_astra_async_complete(AstraAsyncTask *, int, void *);
int32_t network_pending(int32_t id) {
	assert(id > 0 && id < 6 && id != 4);
	assert(atomic_exchange(&observed[id], 1) == 0);
	return 0;
}
int32_t network_pending_ready(int32_t id) {
	assert(id > 0 && id < 6);
	return atomic_load(&observed[id]);
}
int32_t network_finishing(int32_t id) {
	assert(id == 4 && finishing == 0);
	finishing = id;
	return 0;
}
void __wrap_astra_async_complete(AstraAsyncTask *task, int phase, void *exception) {
	__real_astra_async_complete(task, phase, exception);
	if (finishing) {
		/* Native code has published the actual provider success state. The
		 * worker still pins its frame until the resume epilogue returns. */
		assert(finishing == 4 && phase == ASTRA_ASYNC_SUCCESS && exception == NULL);
		assert(atomic_exchange(&observed[finishing], 1) == 0);
		finishing = 0;
	}
}
int32_t network_lifetimes_finish(void) {
	assert(atomic_load(&observed[1]) == 1 && atomic_load(&observed[2]) == 0);
	assert(atomic_load(&observed[3]) == 1 && atomic_load(&observed[4]) == 1 && atomic_load(&observed[5]) == 1);
	net_oracle_lifetimes(5);
	puts("network lifetime: deadline, cold/pending/completed cancellation, shutdown drain, five exact closes");
	return 0;
}
