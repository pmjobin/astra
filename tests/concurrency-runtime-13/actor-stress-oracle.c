// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _GNU_SOURCE
#include <assert.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

enum { MAX_WORKERS = 8,
	   MAX_TICKETS = 131072 };
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static int workers, messages, seed, arrived, received, receiver_drops;
static pthread_t parent, producers[MAX_WORKERS], executor;
static int last[MAX_WORKERS];
static _Atomic int tickets, dropped, active, producer_drops;
static _Atomic unsigned char drops[MAX_TICKETS];

int32_t actor_stress_prepare(int32_t count, int32_t length, int32_t schedule) {
	assert(count >= 2 && count <= MAX_WORKERS && length > 0);
	workers = count;
	messages = length;
	seed = schedule;
	parent = pthread_self();
	for (int i = 0; i < workers; ++i)
		last[i] = -1;
	return 0;
}
int32_t actor_stress_arrive(int32_t id) {
	assert(id >= 0 && id < workers && !pthread_equal(parent, pthread_self()));
	assert(pthread_mutex_lock(&lock) == 0);
	for (int i = 0; i < workers; ++i)
		if (i != id && producers[i]) assert(!pthread_equal(producers[i], pthread_self()));
	producers[id] = pthread_self();
	++arrived;
	assert(pthread_cond_broadcast(&changed) == 0);
	while (arrived != workers)
		assert(pthread_cond_wait(&changed, &lock) == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}
int32_t actor_stress_pause(int32_t sequence) {
	struct timespec delay = {.tv_nsec = 1000 * (1 + (sequence + seed) % 31)};
	assert(nanosleep(&delay, NULL) == 0);
	return 0;
}
int32_t actor_stress_ticket(void) {
	int ticket = atomic_fetch_add(&tickets, 1);
	assert(ticket >= 0 && ticket < MAX_TICKETS);
	return ticket;
}
int32_t actor_stress_drop(int32_t ticket) {
	assert(ticket >= 0 && ticket < atomic_load(&tickets));
	assert(atomic_fetch_add(&drops[ticket], 1) == 0);
	atomic_fetch_add(&dropped, 1);
	return 0;
}
int32_t actor_stress_observe(int32_t id, int32_t sequence, int32_t ticket) {
	assert(atomic_fetch_add(&active, 1) == 0);
	char name[16];
	assert(pthread_getname_np(pthread_self(), name, sizeof(name)) == 0);
	assert(strcmp(name, "actor-stress") == 0);
	assert(id >= 0 && id < workers && sequence >= 0 && sequence < messages);
	assert(ticket >= 0 && ticket < MAX_TICKETS && atomic_load(&drops[ticket]) == 0);
	assert(pthread_mutex_lock(&lock) == 0);
	assert(arrived == workers && sequence == last[id] + 1);
	assert(!pthread_equal(parent, pthread_self()));
	for (int i = 0; i < workers; ++i)
		assert(!pthread_equal(producers[i], pthread_self()));
	if (received == 0)
		executor = pthread_self();
	else
		assert(pthread_equal(executor, pthread_self()));
	last[id] = sequence;
	if ((sequence + seed) % 17 == 0) assert(sched_yield() == 0);
	++received;
	assert(pthread_cond_broadcast(&changed) == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	assert(atomic_fetch_sub(&active, 1) == 1);
	return 0;
}
int32_t actor_stress_wait(void) {
	assert(pthread_mutex_lock(&lock) == 0);
	while (received != workers * messages)
		assert(pthread_cond_wait(&changed, &lock) == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}
int32_t actor_stress_receiver(void) {
	assert(atomic_load(&active) == 0 && receiver_drops++ == 0);
	assert(received == workers * messages);
	return 0;
}
int32_t actor_stress_producer(void) {
	atomic_fetch_add(&producer_drops, 1);
	return 0;
}
int32_t actor_stress_finish(void) {
	assert(receiver_drops == 1 && atomic_load(&producer_drops) == workers);
	assert(atomic_load(&active) == 0 && atomic_load(&dropped) == atomic_load(&tickets));
	for (int i = 0; i < workers; ++i)
		assert(last[i] == messages - 1);
	for (int i = 0; i < atomic_load(&tickets); ++i)
		assert(atomic_load(&drops[i]) == 1);
	printf("native Actor: %d concurrent producers, %d FIFO messages, all attempted owners retired\n", workers, received);
	return 0;
}
