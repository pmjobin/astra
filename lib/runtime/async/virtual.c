/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Standalone cooperative/Linux legacy entry. Link composed.c for coexistence. */
#include "task-core17.c"

static void lock_runtime(void) {}

static void unlock_runtime(void) {}

static int wait_publication(AstraAsyncExecutor *executor) {
	(void)executor;
	return 0;
}

#include "task-api17.c"
