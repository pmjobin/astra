/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "linux.h"
#include <assert.h>
#include <errno.h>
#include <stdio.h>
extern AstraAsyncExecutor *__real_astra_async_linux_open(uint32_t capacity);
extern int __real_astra_async_linux_delay_ms(AstraAsyncTask *task, int64_t milliseconds);
static unsigned errors, observations;
AstraAsyncExecutor *__wrap_astra_async_linux_open(uint32_t capacity) {
	AstraAsyncExecutor *executor = __real_astra_async_linux_open(capacity);
	assert(executor != NULL);
	astra_async_linux_test_fake(executor);
	return executor;
}
int __wrap_astra_async_linux_delay_ms(AstraAsyncTask *task, int64_t milliseconds) {
	int result = __real_astra_async_linux_delay_ms(task, milliseconds);
	assert(result && milliseconds == 10 && errors++ == 0);
	AstraAsyncLinuxSnapshot snapshot;
	assert(astra_async_linux_test_snapshot(astra_async_executor(task), 0, &snapshot) && snapshot.prepared && !snapshot.target_seen);
	assert(astra_async_linux_test_decode(astra_async_executor(task), snapshot.target, -EIO, 0));
	return result;
}
void deferred_observed(int stage) {
	assert(stage == 1 && observations++ == 0);
}
__attribute__((destructor)) static void verify(void) {
	assert(errors == 1 && observations == 1);
	puts("INJECTED EIO reached generated resume-side AsyncError/message catch after target retirement");
}
