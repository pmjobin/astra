// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _POSIX_C_SOURCE 200809L
#include "threads-13.h"
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stddef.h>
#include <stdlib.h>

struct worker {
	uintptr_t identity;
	pthread_t thread;
	pthread_t parent;
	astra_thread_callback callback;
	void *context;
	int32_t argument;
	int32_t result;
	_Atomic int cancelled;
	int joined;
};

static pthread_mutex_t registry_lock = PTHREAD_MUTEX_INITIALIZER;
static struct worker *slots[256];
static uintptr_t next_identity = 1;
static _Thread_local struct worker *current_worker;

static struct worker *lookup(void *token) {
	uintptr_t identity = (uintptr_t)token;
	for (size_t i = 0; i < 256; ++i)
		if (slots[i] && slots[i]->identity == identity)
			return slots[i];
	return NULL;
}

static void *entry(void *argument) {
	struct worker *worker = argument;
	current_worker = worker;
	worker->result = worker->callback(worker->context, worker->argument);
	current_worker = NULL;
	return NULL;
}

void *astra_thread_register(astra_thread_callback callback, void *context, int32_t argument) {
	if (!callback || !context)
		return NULL;
	if (pthread_mutex_lock(&registry_lock) != 0)
		abort();
	size_t slot = 0;
	while (slot < 256 && slots[slot])
		++slot;
	if (slot == 256 || next_identity == UINTPTR_MAX) {
		pthread_mutex_unlock(&registry_lock);
		return NULL;
	}
	struct worker *worker = calloc(1, sizeof(*worker));
	if (!worker) {
		pthread_mutex_unlock(&registry_lock);
		return NULL;
	}
	worker->identity = next_identity++;
	worker->callback = callback;
	worker->context = context;
	worker->argument = argument;
	worker->parent = pthread_self();
	atomic_init(&worker->cancelled, 0);
	if (pthread_create(&worker->thread, NULL, entry, worker) != 0) {
		free(worker);
		pthread_mutex_unlock(&registry_lock);
		return NULL;
	}
	slots[slot] = worker;
	void *token = (void *)worker->identity;
	pthread_mutex_unlock(&registry_lock);
	return token;
}

int32_t astra_thread_join(void *token) {
	if (pthread_mutex_lock(&registry_lock) != 0)
		abort();
	struct worker *worker = lookup(token);
	if (!worker || !pthread_equal(worker->parent, pthread_self())) {
		pthread_mutex_unlock(&registry_lock);
		return -EINVAL;
	}
	// Only the unique parent carrier may join or retire this registration.
	// Registry protection is released while waiting so children can progress.
	pthread_mutex_unlock(&registry_lock);
	if (!worker->joined) {
		if (pthread_join(worker->thread, NULL) != 0)
			abort();
		worker->joined = 1;
	}
	return worker->result;
}

int32_t astra_thread_cancel(void *token) {
	if (pthread_mutex_lock(&registry_lock) != 0)
		abort();
	struct worker *worker = lookup(token);
	if (!worker || !pthread_equal(worker->parent, pthread_self())) {
		pthread_mutex_unlock(&registry_lock);
		return -EINVAL;
	}
	atomic_store_explicit(&worker->cancelled, 1, memory_order_release);
	pthread_mutex_unlock(&registry_lock);
	return 1;
}

int32_t astra_thread_retire(void *token) {
	(void)astra_thread_join(token);
	if (pthread_mutex_lock(&registry_lock) != 0)
		abort();
	struct worker *worker = lookup(token);
	if (!worker || !worker->joined || !pthread_equal(worker->parent, pthread_self())) {
		pthread_mutex_unlock(&registry_lock);
		return 0;
	}
	for (size_t i = 0; i < 256; ++i)
		if (slots[i] == worker)
			slots[i] = NULL;
	pthread_mutex_unlock(&registry_lock);
	free(worker);
	return 1;
}

int32_t astra_worker_cancelled(void) {
	return current_worker ? atomic_load_explicit(&current_worker->cancelled, memory_order_acquire) : 0;
}
