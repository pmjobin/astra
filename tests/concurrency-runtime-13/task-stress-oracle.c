// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static int workers, rounds, arrived, generation, identities;
static int shutdown_released;
static pthread_t parent, threads[8], first[256];
static int visits[256];
static _Atomic int acquired[256], destroyed[256], caught[256], pending[256];

int32_t task_stress_prepare(int32_t count, int32_t batches) {
	assert(count >= 2 && count <= 8 && batches > 0 && batches * count < 250);
	workers = count;
	rounds = batches;
	parent = pthread_self();
	return 0;
}

int32_t task_stress_acquire(int32_t id) {
	assert(id > 0 && id < 256 && atomic_fetch_add(&acquired[id], 1) == 0);
	return 0;
}

int32_t task_stress_destroy(int32_t id) {
	assert(id > 0 && id < 256 && atomic_load(&acquired[id]) == 1);
	assert(atomic_fetch_add(&destroyed[id], 1) == 0);
	return 0;
}

int32_t task_stress_step(int32_t id, int32_t phase) {
	assert(id > 0 && id <= workers * rounds && phase >= 0 && phase <= 1);
	assert(!pthread_equal(parent, pthread_self()));
	assert(pthread_mutex_lock(&lock) == 0);
	assert(visits[id]++ == phase && atomic_load(&destroyed[id]) == 0);
	int known = 0;
	for (int i = 0; i < identities; ++i)
		known |= pthread_equal(threads[i], pthread_self());
	if (!known) {
		assert(identities < workers);
		threads[identities++] = pthread_self();
	}
	if (phase == 0) {
		first[id] = pthread_self();
		int before = generation;
		assert((id - 1) / workers == generation);
		if (++arrived == workers) {
			arrived = 0;
			++generation;
			assert(pthread_cond_broadcast(&changed) == 0);
		} else
			while (before == generation)
				assert(pthread_cond_wait(&changed, &lock) == 0);
	} else
		assert(!pthread_equal(first[id], pthread_self()));
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}

int32_t task_stress_caught(int32_t id) {
	assert(id > 0 && id <= workers * rounds && id % 3 == 0);
	assert(atomic_load(&destroyed[id]) == 1 && atomic_fetch_add(&caught[id], 1) == 0);
	return 0;
}

int32_t task_stress_pending(int32_t id) {
	assert(id > workers * rounds && id < 256 && atomic_fetch_add(&pending[id], 1) == 0);
	if (id == workers * rounds + 3) {
		/* Hold the actual emitted frame between its entry cancellation check
		 * and timer admission until the host has requested shutdown. */
		assert(pthread_mutex_lock(&lock) == 0);
		while (!shutdown_released)
			assert(pthread_cond_wait(&changed, &lock) == 0);
		assert(pthread_mutex_unlock(&lock) == 0);
	}
	return 0;
}

int32_t task_stress_shutdown_released(void) {
	assert(pthread_mutex_lock(&lock) == 0);
	shutdown_released = 1;
	assert(pthread_cond_broadcast(&changed) == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}

int32_t task_stress_ready(int32_t id) {
	assert(id > 0 && id < 256);
	return atomic_load(&pending[id]);
}

int32_t task_stress_finish(int32_t count) {
	assert(count == workers * rounds + 3 && identities == workers && generation == rounds);
	for (int id = 1; id <= count; ++id) {
		assert(atomic_load(&acquired[id]) == 1 && atomic_load(&destroyed[id]) == 1);
		if (id <= workers * rounds)
			assert(visits[id] == 2 && atomic_load(&caught[id]) == (id % 3 == 0));
		else
			assert(atomic_load(&pending[id]) == (id != workers * rounds + 2));
	}
	printf("task stress: %d simultaneous workers, %d migrated batches, checked errors, cold/active/shutdown cleanup\n", workers, rounds);
	return 0;
}
