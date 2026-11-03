// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _POSIX_C_SOURCE 200809L
#include <pthread.h>
#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "monitors-13.h"

/* Compiler-private LP64 intrusive header. The source never receives a raw
 * registry entry, lock, factory callback, or independent destruction token. */
struct shared_root {
	void *descriptor;
	void *origin;
	_Atomic uint64_t strong;
	_Atomic uint64_t weak;
	void *monitor;
	uint64_t thread;
};

_Static_assert(offsetof(struct shared_root, strong) == 16, "intrusive strong ABI");
_Static_assert(offsetof(struct shared_root, weak) == 24, "intrusive weak ABI");
_Static_assert(sizeof(struct shared_root) == 48, "intrusive root ABI");

struct singleton {
	const char *key;
	void *root;
	pthread_t initializer;
	int state; /* 0 uninitialized, 1 constructing, 2 ready, 3 closed */
};

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static struct singleton entries[128];

static struct singleton *find(const char *key) {
	struct singleton *empty = NULL;
	if (key == NULL) abort();
	for (size_t i = 0; i < sizeof(entries) / sizeof(entries[0]); ++i) {
		if (entries[i].key == NULL) {
			if (empty == NULL) empty = &entries[i];
		} else if (strcmp(entries[i].key, key) == 0)
			return &entries[i];
	}
	if (empty == NULL) abort();
	empty->key = key;
	return empty;
}

static void retain(void *pointer) {
	struct shared_root *root = pointer;
	uint64_t expected = atomic_load_explicit(&root->strong, memory_order_acquire);
	for (;;) {
		if (expected == 0 || expected == UINT64_MAX) abort();
		if (atomic_compare_exchange_strong_explicit(&root->strong, &expected,
		                                            expected + 1, memory_order_acq_rel, memory_order_acquire)) return;
	}
}

void *astra_singleton_enter(const char *key) {
	astra_monitor_require_unlocked();
	if (pthread_mutex_lock(&lock) != 0) abort();
	struct singleton *entry = find(key);
	while (entry->state == 1) {
		/* Recursive initialization is refused before waiting on ourselves. */
		if (pthread_equal(entry->initializer, pthread_self())) abort();
		if (pthread_cond_wait(&changed, &lock) != 0) abort();
	}
	void *root = NULL;
	if (entry->state == 3) abort();
	if (entry->state == 2) {
		root = entry->root;
		retain(root);
	} else {
		entry->state = 1;
		entry->initializer = pthread_self();
	}
	if (pthread_mutex_unlock(&lock) != 0) abort();
	return root;
}

void astra_singleton_publish(const char *key, void *pointer) {
	if (pthread_mutex_lock(&lock) != 0) abort();
	struct singleton *entry = find(key);
	if (entry->state != 1 || !pthread_equal(entry->initializer, pthread_self()) || pointer == NULL) abort();
	retain(pointer); /* The registry owns one ordinary strong reference. */
	entry->root = pointer;
	entry->state = 2;
	if (pthread_cond_broadcast(&changed) != 0 || pthread_mutex_unlock(&lock) != 0) abort();
}

void astra_singleton_abort(const char *key) {
	if (pthread_mutex_lock(&lock) != 0) abort();
	struct singleton *entry = find(key);
	if (entry->state != 1 || !pthread_equal(entry->initializer, pthread_self())) abort();
	entry->state = 0;
	if (pthread_cond_broadcast(&changed) != 0 || pthread_mutex_unlock(&lock) != 0) abort();
}

int32_t astra_singleton_detach(const char *key, void *pointer) {
	if (pthread_mutex_lock(&lock) != 0) abort();
	struct singleton *entry = find(key);
	int32_t result = 0;
	if (entry->state == 2 && entry->root == pointer &&
	    atomic_load_explicit(&((struct shared_root *)pointer)->strong, memory_order_acquire) == 2) {
		entry->root = NULL;
		entry->state = 3;
		result = 1;
	}
	if (pthread_mutex_unlock(&lock) != 0) abort();
	return result;
}
