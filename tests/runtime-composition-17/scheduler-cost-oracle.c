// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _GNU_SOURCE
#include <assert.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* Measurement only. Counts include independent test observers and libc users;
 * measured acquisition duration includes clock/interposition overhead. */
static int (*real_lock)(pthread_mutex_t *);
static int (*real_wait)(pthread_cond_t *, pthread_mutex_t *);
static int (*real_timedwait)(pthread_cond_t *, pthread_mutex_t *, const struct timespec *);
static int (*real_broadcast)(pthread_cond_t *);
static _Atomic uint64_t locks, lock_ns, slow_locks, waits, timed_waits, timeouts, broadcasts;

/* Samples match an actual condition address and a broadcast timestamp inside
 * the wait interval. They include mutex reacquisition and observer overhead;
 * spurious returns and concurrent broadcasts prevent a causal wake guarantee. */
typedef struct {
	_Atomic uintptr_t condition;
	_Atomic uint64_t broadcast_ns;
} WakeSlot;

static WakeSlot wake_slots[64];
static _Atomic uint64_t wake_samples, wake_ns, wake_max_ns, wake_slots_full;

#define RESOLVE(name, symbol_name) do { \
	void *symbol = dlsym(RTLD_NEXT, symbol_name); \
	_Static_assert(sizeof(real_##name) == sizeof(symbol), "selected ELF function pointer ABI"); \
	assert(symbol); memcpy(&real_##name, &symbol, sizeof(symbol)); \
} while (0)

__attribute__((constructor)) static void initialize(void) {
	RESOLVE(lock, "pthread_mutex_lock");
	RESOLVE(wait, "pthread_cond_wait");
	RESOLVE(timedwait, "pthread_cond_timedwait");
	RESOLVE(broadcast, "pthread_cond_broadcast");
}

static uint64_t nanoseconds(void) {
	struct timespec value;
	assert(clock_gettime(CLOCK_MONOTONIC, &value) == 0);
	return (uint64_t)value.tv_sec * UINT64_C(1000000000) + (uint64_t)value.tv_nsec;
}

static WakeSlot *wake_slot(pthread_cond_t *condition) {
	uintptr_t key = (uintptr_t)condition;
	assert(key);
	for (unsigned i = 0; i < 64; ++i) {
		uintptr_t empty = 0;
		if (atomic_load(&wake_slots[i].condition) == key || atomic_compare_exchange_strong(&wake_slots[i].condition, &empty, key) || empty == key) {
			return &wake_slots[i];
		}
	}
	atomic_fetch_add(&wake_slots_full, 1);
	return NULL;
}

static void observed_return(pthread_cond_t *condition, uint64_t began, int result) {
	uint64_t ended = nanoseconds();
	if (result) {
		return;
	}
	WakeSlot *slot = wake_slot(condition);
	if (!slot) {
		return;
	}
	uint64_t broadcast = atomic_load(&slot->broadcast_ns);
	if (broadcast < began || broadcast > ended) {
		return;
	}
	uint64_t elapsed = ended - broadcast, maximum = atomic_load(&wake_max_ns);
	atomic_fetch_add(&wake_samples, 1);
	atomic_fetch_add(&wake_ns, elapsed);
	while (maximum < elapsed && !atomic_compare_exchange_weak(&wake_max_ns, &maximum, elapsed)) {
	}
}

int pthread_mutex_lock(pthread_mutex_t *mutex) {
	assert(real_lock);
	uint64_t before = nanoseconds();
	int result = real_lock(mutex);
	uint64_t elapsed = nanoseconds() - before;
	if (!result) {
		atomic_fetch_add_explicit(&locks, 1, memory_order_relaxed);
		atomic_fetch_add_explicit(&lock_ns, elapsed, memory_order_relaxed);
		if (elapsed >= 10000) atomic_fetch_add_explicit(&slow_locks, 1, memory_order_relaxed);
	}
	return result;
}

int pthread_cond_wait(pthread_cond_t *condition, pthread_mutex_t *mutex) {
	assert(real_wait);
	atomic_fetch_add_explicit(&waits, 1, memory_order_relaxed);
	uint64_t began = nanoseconds();
	int result = real_wait(condition, mutex);
	observed_return(condition, began, result);
	return result;
}

int pthread_cond_timedwait(pthread_cond_t *condition, pthread_mutex_t *mutex, const struct timespec *deadline) {
	assert(real_timedwait);
	atomic_fetch_add_explicit(&timed_waits, 1, memory_order_relaxed);
	uint64_t began = nanoseconds();
	int result = real_timedwait(condition, mutex, deadline);
	observed_return(condition, began, result);
	if (result == ETIMEDOUT) atomic_fetch_add_explicit(&timeouts, 1, memory_order_relaxed);
	return result;
}

int pthread_cond_broadcast(pthread_cond_t *condition) {
	assert(real_broadcast);
	atomic_fetch_add_explicit(&broadcasts, 1, memory_order_relaxed);
	WakeSlot *slot = wake_slot(condition);
	if (slot) {
		atomic_store(&slot->broadcast_ns, nanoseconds());
	}
	return real_broadcast(condition);
}

__attribute__((destructor)) static void finish(void) {
	const char *path = getenv("ASTRA_SCHEDULER_OBSERVER_LOG");
	assert(path);
	char buffer[1024];
	int count = snprintf(buffer, sizeof(buffer),
	                     "{\"locks\":%llu,\"lock_acquisition_ns\":%llu,\"acquisitions_at_least_10us\":%llu,"
	                     "\"condition_waits\":%llu,\"condition_timed_waits\":%llu,\"timeouts\":%llu,\"broadcasts\":%llu,"
	                     "\"wake_samples\":%llu,\"broadcast_to_wait_return_ns\":%llu,\"broadcast_to_wait_return_max_ns\":%llu,\"wake_slots_full\":%llu}\n",
	                     (unsigned long long)atomic_load(&locks), (unsigned long long)atomic_load(&lock_ns),
	                     (unsigned long long)atomic_load(&slow_locks), (unsigned long long)atomic_load(&waits),
	                     (unsigned long long)atomic_load(&timed_waits), (unsigned long long)atomic_load(&timeouts),
	                     (unsigned long long)atomic_load(&broadcasts), (unsigned long long)atomic_load(&wake_samples),
	                     (unsigned long long)atomic_load(&wake_ns), (unsigned long long)atomic_load(&wake_max_ns),
	                     (unsigned long long)atomic_load(&wake_slots_full));
	assert(count > 0 && (size_t)count < sizeof(buffer));
	int output = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
	assert(output >= 0 && write(output, buffer, (size_t)count) == count);
	assert(close(output) == 0);
}
