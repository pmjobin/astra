// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _GNU_SOURCE
#include <assert.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Optional measurement interposer, never part of production runtime linkage.
// Counts include the independently compiled observers and ordinary libc entry.
static int (*real_lock)(pthread_mutex_t *);
static int (*real_create)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
static _Atomic uint64_t locks, threads;

__attribute__((constructor)) static void initialize(void) {
	void *entry = dlsym(RTLD_NEXT, "pthread_mutex_lock");
	_Static_assert(sizeof(real_lock) == sizeof(entry), "selected ELF function pointer ABI");
	assert(entry);
	memcpy(&real_lock, &entry, sizeof(entry));
	entry = dlsym(RTLD_NEXT, "pthread_create");
	assert(entry);
	memcpy(&real_create, &entry, sizeof(entry));
}

int pthread_mutex_lock(pthread_mutex_t *mutex) {
	assert(real_lock);
	int result = real_lock(mutex);
	if (!result) atomic_fetch_add_explicit(&locks, 1, memory_order_relaxed);
	return result;
}

int pthread_create(pthread_t *thread, const pthread_attr_t *attributes, void *(*entry)(void *), void *context) {
	assert(real_create);
	int result = real_create(thread, attributes, entry, context);
	if (!result) atomic_fetch_add_explicit(&threads, 1, memory_order_relaxed);
	return result;
}

__attribute__((destructor)) static void finish(void) {
	const char *path = getenv("ASTRA_COST_OBSERVER_LOG");
	assert(path);
	uint64_t count = atomic_load_explicit(&locks, memory_order_relaxed);
	uint64_t created = atomic_load_explicit(&threads, memory_order_relaxed);
	char buffer[160];
	int length = snprintf(buffer, sizeof(buffer), "{\"successful_explicit_mutex_locks\":%llu,\"threads_created\":%llu}\n", (unsigned long long)count, (unsigned long long)created);
	assert(length > 0 && (size_t)length < sizeof(buffer));
	int output = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
	assert(output >= 0 && write(output, buffer, (size_t)length) == length);
	assert(close(output) == 0);
}
