// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _POSIX_C_SOURCE 200809L
#include "monitors-13.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>

struct monitor {
	pthread_mutex_t mutex;
};

static _Atomic uint64_t next_thread = 1;
static _Thread_local uint64_t thread_identity;
static _Thread_local struct monitor *held_monitor;
static _Thread_local unsigned held_depth;
static _Thread_local unsigned internal_entry;

uint64_t astra_concurrency_thread_identity(void) {
	if (!thread_identity) {
		thread_identity = atomic_fetch_add_explicit(&next_thread, 1, memory_order_relaxed);
		if (!thread_identity || thread_identity == UINT64_MAX)
			abort();
	}
	return thread_identity;
}

void astra_concurrency_thread_check(uint64_t expected) {
	if (expected != astra_concurrency_thread_identity())
		abort();
}

void *astra_monitor_create(void) {
	struct monitor *monitor = malloc(sizeof(*monitor));
	if (!monitor || pthread_mutex_init(&monitor->mutex, NULL) != 0)
		abort();
	return monitor;
}

void astra_monitor_internal(void *opaque) {
	if (held_monitor != opaque || !held_depth || internal_entry)
		abort();
	internal_entry = 1;
}

void astra_monitor_enter(void *opaque) {
	struct monitor *monitor = opaque;
	if (!monitor)
		abort();
	if (held_monitor) {
		// Only an immediately preceding compiler-proved direct this-call may
		// reuse its own guard. Unknown reentry and cross-object nesting fail.
		if (held_monitor != monitor || !internal_entry || held_depth == 1024)
			abort();
		internal_entry = 0;
		++held_depth;
		return;
	}
	if (internal_entry || pthread_mutex_lock(&monitor->mutex) != 0)
		abort();
	held_monitor = monitor;
	held_depth = 1;
}

void astra_monitor_leave(void *opaque) {
	if (held_monitor != opaque || !held_depth || internal_entry)
		abort();
	if (--held_depth)
		return;
	held_monitor = NULL;
	if (pthread_mutex_unlock(&((struct monitor *)opaque)->mutex) != 0)
		abort();
}

void astra_monitor_destroy(void *opaque) {
	if (!opaque || held_monitor == opaque || pthread_mutex_destroy(&((struct monitor *)opaque)->mutex) != 0)
		abort();
	free(opaque);
}

void astra_monitor_require_unlocked(void) {
	if (held_monitor || held_depth || internal_entry)
		abort();
}
