/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "linux.h"
#include <assert.h>
#include <errno.h>
#include <stdio.h>
static unsigned inputs, waits, caught;
extern AstraAsyncExecutor *__real_astra_async_linux_open(uint32_t capacity);
extern int __real_astra_async_linux_delay_ms(AstraAsyncTask *task, int64_t milliseconds);

AstraAsyncExecutor *__wrap_astra_async_linux_open(uint32_t capacity) {
	AstraAsyncExecutor *executor = __real_astra_async_linux_open(capacity);
	assert(executor != NULL);
	astra_async_linux_test_fake(executor);
	return executor;
}

int duration_input(void) {
	assert(inputs++ == 0);
	return -1;
}

int __wrap_astra_async_linux_delay_ms(AstraAsyncTask *task, int64_t milliseconds) {
	int result = __real_astra_async_linux_delay_ms(task, milliseconds);
	if (milliseconds < 0) {
		assert(waits == 2 && milliseconds == -1 && !result);
		AstraAsyncLinuxFailure failure = astra_async_linux_last_failure();
		assert(failure.operation == ASTRA_LINUX_DURATION && failure.error == EINVAL);
		return result;
	}
	AstraAsyncLinuxSnapshot snapshot;
	assert(astra_async_linux_test_snapshot(astra_async_executor(task), 0, &snapshot));
	assert(result && snapshot.prepared && !snapshot.target_seen && snapshot.generation == waits + 1);
	assert(milliseconds == (waits == 0 ? UINT32_MAX : 0) && snapshot.ns == (waits == 0 ? UINT64_C(4294967295000000) : 0));
	waits++;
	assert(astra_async_linux_test_decode(astra_async_executor(task), snapshot.target, -ETIME, 0));
	return result;
}

void duration_observed(int stage) {
	assert(stage == 1 && caught++ == 0);
}

__attribute__((destructor)) static void verify(void) {
	assert(inputs == 1 && waits == 2 && caught == 1);
	puts("INJECTED generated duration boundary: u32 max widens once to exact ns; zero handshake; signed negative admission reaches AsyncError");
}
