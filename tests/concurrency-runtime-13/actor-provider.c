// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Provider supplement only. Native Astra Actor qualification is separate.
#define _GNU_SOURCE
#include "../../lib/runtime/runtime/actors-13.h"
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static pthread_mutex_t gate = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static int entered, proceed, received;
static _Atomic int executing, receiver_drops, message_drops[5];
static void *sender;
struct receiver {
	int last[8];
};
struct message {
	int id;
};
static void drop_receiver(void *opaque) {
	assert(atomic_load(&executing) == 0);
	atomic_fetch_add(&receiver_drops, 1);
	free(opaque);
}
static void drop_message(void *opaque) {
	struct message *message = opaque;
	assert(message && message->id >= 0 && message->id < 5);
	assert(atomic_fetch_add(&message_drops[message->id], 1) == 0);
	free(message);
}
static void *message(int id) {
	struct message *result = malloc(sizeof(*result));
	assert(result);
	result->id = id;
	return result;
}
static void blocked_handler(void *receiver, void *opaque, uint64_t scalar) {
	(void)receiver;
	(void)scalar;
	assert(atomic_fetch_add(&executing, 1) == 0);
	char name[16];
	assert(pthread_getname_np(pthread_self(), name, sizeof(name)) == 0 && strcmp(name, "actor-test") == 0);
	assert(astra_actor_shutdown(sender) == -EDEADLK);
	struct message *value = opaque;
	assert(value->id == 0);
	assert(pthread_mutex_lock(&gate) == 0);
	entered = 1;
	assert(pthread_cond_broadcast(&changed) == 0);
	while (!proceed)
		assert(pthread_cond_wait(&changed, &gate) == 0);
	assert(pthread_mutex_unlock(&gate) == 0);
	assert(astra_actor_cancelled() == 1);
	drop_message(opaque);
	assert(atomic_fetch_sub(&executing, 1) == 1);
}
static void scalar_handler(void *opaque, void *message, uint64_t scalar) {
	assert(!message && atomic_fetch_add(&executing, 1) == 0);
	char name[16];
	assert(pthread_getname_np(pthread_self(), name, sizeof(name)) == 0 && strcmp(name, "actor-count") == 0);
	int producer = scalar / 1000, sequence = scalar % 1000;
	struct receiver *receiver = opaque;
	assert(producer >= 0 && producer < 8 && sequence == receiver->last[producer] + 1);
	receiver->last[producer] = sequence;
	assert(pthread_mutex_lock(&gate) == 0);
	++received;
	assert(pthread_cond_broadcast(&changed) == 0);
	assert(pthread_mutex_unlock(&gate) == 0);
	assert(atomic_fetch_sub(&executing, 1) == 1);
}
struct producer {
	void *sender;
	int id;
};
static void *produce(void *opaque) {
	struct producer *producer = opaque;
	for (int i = 0; i < 100; ++i) {
		int32_t status;
		do {
			status = astra_actor_send(producer->sender, NULL, producer->id * 1000 + i, NULL);
			if (status == -EAGAIN) {
				struct timespec delay = {.tv_nsec = 1000000};
				assert(nanosleep(&delay, NULL) == 0);
			}
		} while (status == -EAGAIN);
		assert(status == 0);
	}
	astra_actor_release(producer->sender);
	return NULL;
}
int main(void) {
	alarm(20);
	sender = astra_actor_open(blocked_handler, calloc(1, sizeof(struct receiver)), drop_receiver, drop_message, 2, "actor-test", 10);
	assert(sender);
	void *clone = astra_actor_clone(sender);
	assert(clone == sender);
	assert(astra_actor_send(sender, message(0), 0, drop_message) == 0);
	assert(pthread_mutex_lock(&gate) == 0);
	while (!entered)
		assert(pthread_cond_wait(&changed, &gate) == 0);
	assert(pthread_mutex_unlock(&gate) == 0);
	assert(astra_actor_send(clone, message(1), 0, drop_message) == 0);
	assert(astra_actor_send(clone, message(2), 0, drop_message) == 0);
	assert(astra_actor_send(clone, message(3), 0, drop_message) == -EAGAIN);
	assert(astra_actor_cancel(sender) == 2);
	assert(pthread_mutex_lock(&gate) == 0);
	proceed = 1;
	assert(pthread_cond_broadcast(&changed) == 0);
	assert(pthread_mutex_unlock(&gate) == 0);
	assert(astra_actor_shutdown(sender) == 0);
	assert(astra_actor_send(sender, message(4), 0, drop_message) == -EPIPE);
	for (int i = 0; i < 5; ++i)
		assert(atomic_load(&message_drops[i]) == 1);
	astra_actor_release(clone);
	astra_actor_release(sender);
	assert(atomic_load(&receiver_drops) == 1);
	struct receiver *receiver = calloc(1, sizeof(*receiver));
	assert(receiver);
	for (int i = 0; i < 8; ++i)
		receiver->last[i] = -1;
	sender = astra_actor_open(scalar_handler, receiver, drop_receiver, NULL, 8, "actor-count", 11);
	assert(sender);
	pthread_t threads[4];
	struct producer producers[4];
	for (int i = 0; i < 4; ++i) {
		producers[i] = (struct producer){astra_actor_clone(sender), i};
		assert(pthread_create(&threads[i], NULL, produce, &producers[i]) == 0);
	}
	for (int i = 0; i < 4; ++i)
		assert(pthread_join(threads[i], NULL) == 0);
	assert(pthread_mutex_lock(&gate) == 0);
	while (received != 400)
		assert(pthread_cond_wait(&changed, &gate) == 0);
	assert(pthread_mutex_unlock(&gate) == 0);
	assert(astra_actor_shutdown(sender) == 0);
	astra_actor_release(sender);
	assert(atomic_load(&receiver_drops) == 2 && atomic_load(&executing) == 0);
	puts("Actor provider supplement: bounded FIFO, full/closed consumption, queued cancel, active cancellation, named executor and joins");
	return 0;
}
