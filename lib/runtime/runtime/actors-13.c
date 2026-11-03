// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _GNU_SOURCE
#include "actors-13.h"
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum { MAX_ACTORS = 64,
	   MAX_MAILBOX = 1024 };

struct message {
	void *owner;
	uint64_t scalar;
};

struct actor {
	_Atomic uint64_t strong;
	pthread_mutex_t lock;
	pthread_cond_t changed;
	pthread_t worker;
	struct message *queue;
	uint32_t capacity, head, size;
	uint64_t retiring;
	int closed, joining, joined, running;
	_Atomic int cancel;
	AstraActorDispatch dispatch;
	AstraActorDrop drop_receiver, drop_message;
	void *receiver;
	char name[16];
};

static _Atomic unsigned active_actors;
static _Thread_local struct actor *current_actor;

static void require(int condition) {
	if (!condition) abort();
}

static void lock(struct actor *actor) {
	require(pthread_mutex_lock(&actor->lock) == 0);
}

static void unlock(struct actor *actor) {
	require(pthread_mutex_unlock(&actor->lock) == 0);
}

static void changed(struct actor *actor) {
	require(pthread_cond_broadcast(&actor->changed) == 0);
}

static uint32_t detach(struct actor *actor, struct message retired[MAX_MAILBOX]) {
	uint32_t count = actor->size;
	for (uint32_t i = 0; i < count; ++i) {
		uint32_t index = (actor->head + i) % actor->capacity;
		retired[i] = actor->queue[index];
		actor->queue[index] = (struct message){0};
	}
	actor->head = 0;
	actor->size = 0;
	require(UINT64_MAX - actor->retiring >= count);
	actor->retiring += count;
	return count;
}

static void discard(struct actor *actor, struct message *messages, uint32_t count) {
	if (actor->drop_message)
		for (uint32_t i = 0; i < count; ++i)
			actor->drop_message(messages[i].owner);
	if (count) {
		lock(actor);
		require(actor->retiring >= count);
		actor->retiring -= count;
		changed(actor);
		unlock(actor);
	}
}

static void *execute(void *opaque) {
	struct actor *actor = opaque;
	current_actor = actor;
	require(pthread_setname_np(pthread_self(), actor->name) == 0);
	lock(actor);
	for (;;) {
		while (actor->size == 0 && !actor->closed)
			require(pthread_cond_wait(&actor->changed, &actor->lock) == 0);
		if (actor->size == 0 && actor->closed) break;
		struct message message = actor->queue[actor->head];
		actor->queue[actor->head] = (struct message){0};
		actor->head = (actor->head + 1) % actor->capacity;
		--actor->size;
		actor->running = 1;
		atomic_store_explicit(&actor->cancel, 0, memory_order_release);
		unlock(actor);
		/* The compiler's exact C thunk transfers the message into one native
		 * owning handler parameter. Only that handler retires an active item. */
		actor->dispatch(actor->receiver, message.owner, message.scalar);
		lock(actor);
		actor->running = 0;
		changed(actor);
	}
	unlock(actor);
	current_actor = NULL;
	return NULL;
}

static int reserve_actor(void) {
	unsigned expected = atomic_load_explicit(&active_actors, memory_order_acquire);
	for (;;) {
		if (expected >= MAX_ACTORS) return 0;
		if (atomic_compare_exchange_strong_explicit(&active_actors, &expected,
		                                            expected + 1, memory_order_acq_rel, memory_order_acquire)) return 1;
	}
}

void *astra_actor_open(AstraActorDispatch dispatch, void *receiver,
                       AstraActorDrop drop_receiver, AstraActorDrop drop_message,
                       int32_t capacity, const char *name, int32_t name_length) {
	if (!dispatch || !receiver || !drop_receiver || capacity < 1 || capacity > MAX_MAILBOX ||
	    !name || name_length < 1 || name_length > 15) abort();
	for (int i = 0; i < name_length; ++i)
		require(name[i] >= 32 && name[i] <= 126);
	if (!reserve_actor()) {
		drop_receiver(receiver);
		return NULL;
	}
	struct actor *actor = calloc(1, sizeof(*actor));
	if (!actor) goto failed;
	actor->queue = calloc((size_t)capacity, sizeof(*actor->queue));
	if (!actor->queue) {
		free(actor);
		goto failed;
	}
	if (pthread_mutex_init(&actor->lock, NULL) != 0) {
		free(actor->queue);
		free(actor);
		goto failed;
	}
	if (pthread_cond_init(&actor->changed, NULL) != 0) {
		require(pthread_mutex_destroy(&actor->lock) == 0);
		free(actor->queue);
		free(actor);
		goto failed;
	}
	atomic_init(&actor->strong, 1);
	atomic_init(&actor->cancel, 0);
	actor->capacity = (uint32_t)capacity;
	actor->receiver = receiver;
	actor->dispatch = dispatch;
	actor->drop_receiver = drop_receiver;
	actor->drop_message = drop_message;
	memcpy(actor->name, name, (size_t)name_length);
	if (pthread_create(&actor->worker, NULL, execute, actor) != 0) {
		require(pthread_cond_destroy(&actor->changed) == 0);
		require(pthread_mutex_destroy(&actor->lock) == 0);
		free(actor->queue);
		free(actor);
		goto failed;
	}
	return actor;
failed:
	atomic_fetch_sub_explicit(&active_actors, 1, memory_order_acq_rel);
	drop_receiver(receiver);
	return NULL;
}

void *astra_actor_clone(void *opaque) {
	struct actor *actor = opaque;
	if (!actor) return NULL;
	uint64_t expected = atomic_load_explicit(&actor->strong, memory_order_acquire);
	for (;;) {
		require(expected != 0 && expected != UINT64_MAX);
		if (atomic_compare_exchange_strong_explicit(&actor->strong, &expected,
		                                            expected + 1, memory_order_acq_rel, memory_order_acquire)) return actor;
	}
}

int32_t astra_actor_send(void *opaque, void *message, uint64_t scalar, AstraActorDrop drop) {
	struct actor *actor = opaque;
	if (!actor) {
		if (drop) drop(message);
		return -EPIPE;
	}
	require(drop == actor->drop_message);
	int32_t status = 0;
	lock(actor);
	if (actor->closed)
		status = -EPIPE;
	else if (drop && !message)
		status = -EINVAL;
	else if (actor->size == actor->capacity)
		status = -EAGAIN;
	else {
		uint32_t tail = (actor->head + actor->size) % actor->capacity;
		actor->queue[tail] = (struct message){.owner = message, .scalar = scalar};
		++actor->size;
		changed(actor);
	}
	unlock(actor);
	/* Every rejected ownership responsibility is retired outside the queue
	 * mutex before the compiler constructs the checked source exception. */
	if (status != 0 && drop) drop(message);
	return status;
}

int32_t astra_actor_cancel(void *opaque) {
	struct actor *actor = opaque;
	if (!actor) return 0;
	struct message retired[MAX_MAILBOX];
	lock(actor);
	uint32_t count = detach(actor, retired);
	atomic_store_explicit(&actor->cancel, 1, memory_order_release);
	changed(actor);
	unlock(actor);
	discard(actor, retired, count);
	return (int32_t)count;
}

int32_t astra_actor_shutdown(void *opaque) {
	struct actor *actor = opaque;
	if (!actor) return 0;
	/* Refuse synchronous self-wait before entering a join protocol. */
	if (current_actor == actor) return -EDEADLK;
	struct message retired[MAX_MAILBOX];
	lock(actor);
	while (actor->joining && !actor->joined)
		require(pthread_cond_wait(&actor->changed, &actor->lock) == 0);
	if (actor->joined) {
		unlock(actor);
		return 0;
	}
	actor->joining = 1;
	actor->closed = 1;
	uint32_t count = detach(actor, retired);
	atomic_store_explicit(&actor->cancel, 1, memory_order_release);
	changed(actor);
	unlock(actor);
	discard(actor, retired, count);
	require(pthread_join(actor->worker, NULL) == 0);
	/* Another sender may already have detached cancelled messages. Joining
	 * the executor alone cannot retire those producer-side destructors. */
	lock(actor);
	while (actor->retiring)
		require(pthread_cond_wait(&actor->changed, &actor->lock) == 0);
	unlock(actor);
	actor->drop_receiver(actor->receiver);
	lock(actor);
	actor->receiver = NULL;
	actor->joined = 1;
	actor->joining = 0;
	changed(actor);
	unlock(actor);
	return 0;
}

void astra_actor_release(void *opaque) {
	struct actor *actor = opaque;
	if (!actor) return;
	uint64_t expected = atomic_load_explicit(&actor->strong, memory_order_acquire);
	for (;;) {
		require(expected != 0);
		if (atomic_compare_exchange_strong_explicit(&actor->strong, &expected,
		                                            expected - 1, memory_order_acq_rel, memory_order_acquire)) break;
	}
	if (expected != 1) return;
	require(astra_actor_shutdown(actor) == 0);
	require(pthread_mutex_destroy(&actor->lock) == 0 && pthread_cond_destroy(&actor->changed) == 0);
	free(actor->queue);
	free(actor);
	require(atomic_fetch_sub_explicit(&active_actors, 1, memory_order_acq_rel) != 0);
}

int32_t astra_actor_cancelled(void) {
	return current_actor ? atomic_load_explicit(&current_actor->cancel, memory_order_acquire) : 0;
}
