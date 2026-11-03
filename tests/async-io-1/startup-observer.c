/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "linux.h"
#include <assert.h>
#include <errno.h>
#include <liburing.h>
#include <stdio.h>
static unsigned attempts;

int __wrap_io_uring_queue_init_params(unsigned entries, struct io_uring *ring, struct io_uring_params *params) {
	(void)ring;
	assert(entries == 32 && params->cq_entries == 64);
	attempts++;
	return -EPERM;
}

__attribute__((destructor)) static void verify(void) {
	AstraAsyncLinuxFailure failure = astra_async_linux_last_failure();
	assert(attempts == 1 && failure.operation == ASTRA_LINUX_SETUP && failure.error == EPERM);
	puts("INJECTED setup EPERM: generated AsyncError catch, stable typed stage/errno and message");
}
