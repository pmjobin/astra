// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Runtime supplement: cancellation on one sender races a joined shutdown.
#include "../../lib/runtime/runtime/actors-13.h"
#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static pthread_mutex_t gate = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static int active, release_active, retiring, release_retired, shutdown_waiting;
static _Thread_local int shutdown_thread;
static _Atomic int drops[2], receivers;
static void *root;

struct parcel {
	int id;
};

int __real_pthread_cond_wait(pthread_cond_t *, pthread_mutex_t *);

int __wrap_pthread_cond_wait(pthread_cond_t *condition, pthread_mutex_t *mutex) {
	if (shutdown_thread && mutex != &gate) {
		assert(pthread_mutex_lock(&gate) == 0);
		shutdown_waiting = 1;
		assert(pthread_cond_broadcast(&changed) == 0);
		assert(pthread_mutex_unlock(&gate) == 0);
	}
	return __real_pthread_cond_wait(condition, mutex);
}

static void drop(void *opaque) {
	struct parcel *parcel = opaque;
	assert(parcel && parcel->id >= 0 && parcel->id < 2);
	if (parcel->id == 1) {
		assert(pthread_mutex_lock(&gate) == 0);
		retiring = 1;
		assert(pthread_cond_broadcast(&changed) == 0);
		while (!release_retired)
			assert(pthread_cond_wait(&changed, &gate) == 0);
		assert(pthread_mutex_unlock(&gate) == 0);
	}
	assert(atomic_fetch_add(&drops[parcel->id], 1) == 0);
	free(parcel);
}

static void receive(void *receiver, void *message, uint64_t scalar) {
	(void)receiver;
	(void)scalar;
	assert(((struct parcel *)message)->id == 0);
	assert(pthread_mutex_lock(&gate) == 0);
	active = 1;
	assert(pthread_cond_broadcast(&changed) == 0);
	while (!release_active)
		assert(pthread_cond_wait(&changed, &gate) == 0);
	assert(pthread_mutex_unlock(&gate) == 0);
	drop(message);
}

static void drop_receiver(void *receiver) {
	assert(atomic_load(&drops[0]) == 1 && atomic_load(&drops[1]) == 1);
	assert(atomic_fetch_add(&receivers, 1) == 0);
	free(receiver);
}

static void *cancel(void *sender) {
	assert(astra_actor_cancel(sender) == 1);
	astra_actor_release(sender);
	return NULL;
}

static void *shutdown_actor(void *sender) {
	shutdown_thread = 1;
	assert(astra_actor_shutdown(sender) == 0);
	astra_actor_release(sender);
	return NULL;
}

int main(void) {
	alarm(15);
	root = astra_actor_open(receive, malloc(1), drop_receiver, drop, 2, "actor-retire", 12);
	assert(root);
	struct parcel *first = malloc(sizeof(*first)), *second = malloc(sizeof(*second));
	assert(first && second);
	first->id = 0;
	second->id = 1;
	assert(astra_actor_send(root, first, 0, drop) == 0);
	assert(pthread_mutex_lock(&gate) == 0);
	while (!active)
		assert(pthread_cond_wait(&changed, &gate) == 0);
	assert(pthread_mutex_unlock(&gate) == 0);
	assert(astra_actor_send(root, second, 0, drop) == 0);
	pthread_t canceller, joiner;
	assert(pthread_create(&canceller, NULL, cancel, astra_actor_clone(root)) == 0);
	assert(pthread_mutex_lock(&gate) == 0);
	while (!retiring)
		assert(pthread_cond_wait(&changed, &gate) == 0);
	release_active = 1;
	assert(pthread_cond_broadcast(&changed) == 0);
	assert(pthread_mutex_unlock(&gate) == 0);
	assert(pthread_create(&joiner, NULL, shutdown_actor, astra_actor_clone(root)) == 0);
	assert(pthread_mutex_lock(&gate) == 0);
	while (!shutdown_waiting)
		assert(pthread_cond_wait(&changed, &gate) == 0);
	assert(atomic_load(&receivers) == 0 && atomic_load(&drops[1]) == 0);
	release_retired = 1;
	assert(pthread_cond_broadcast(&changed) == 0);
	assert(pthread_mutex_unlock(&gate) == 0);
	assert(pthread_join(canceller, NULL) == 0 && pthread_join(joiner, NULL) == 0);
	astra_actor_release(root);
	assert(atomic_load(&receivers) == 1);
	puts("Actor runtime supplement: shutdown waits for concurrent queued-message retirement");
	return 0;
}
