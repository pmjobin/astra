// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Private runtime ABI supplement; the separate application corpus executes
// compiler-generated owning native frames and task parents.
#include "../../lib/runtime/async/virtual.h"
#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>

typedef struct State {
	int root;
} State;

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static int entered, proceed;
static _Atomic int destroyed;

static void dispose(AstraAsyncTask *task, int discard) {
	(void)task;
	assert(discard);
	atomic_fetch_add(&destroyed, 1);
}

static void resume(AstraAsyncTask *task) {
	if (astra_async_cancel_requested(task)) {
		if (astra_async_cancel_scope(task)) astra_async_complete(task, ASTRA_ASYNC_CANCELLED, NULL);
		return;
	}
	assert(astra_async_pc(task) == 0);
	astra_async_set_pc(task, 1);
	State *state = astra_async_data(task);
	if (state->root) {
		assert(pthread_mutex_lock(&lock) == 0);
		entered = 1;
		assert(pthread_cond_broadcast(&changed) == 0);
		while (!proceed)
			assert(pthread_cond_wait(&changed, &lock) == 0);
		assert(pthread_mutex_unlock(&lock) == 0);
	}
	assert(astra_async_delay(task, 60000));
}

static AstraAsyncTask *create(AstraAsyncTask *parent, int root) {
	AstraAsyncTask *task = astra_async_new(sizeof(State), _Alignof(State), resume, dispose, parent);
	*(State *)astra_async_data(task) = (State){.root = root};
	return task;
}

int main(void) {
	AstraAsyncExecutor *executor = astra_async_open(2), *other = astra_async_open(2);
	assert(executor && other);
	AstraAsyncTask *root = create(NULL, 1);
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	assert(pthread_mutex_lock(&lock) == 0);
	while (!entered)
		assert(pthread_cond_wait(&changed, &lock) == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	AstraAsyncTask *children[255];
	for (int i = 0; i < 255; ++i) {
		children[i] = create(root, 0);
		assert(astra_async_start(executor, children[i], root) == ASTRA_ASYNC_ADMITTED);
	}
	AstraAsyncToken stale = astra_async_token(children[0]);
	assert(astra_async_start(other, children[0], root) == ASTRA_ASYNC_ASSOCIATION);
	AstraAsyncTask *overflow = create(root, 0);
	assert(astra_async_start(executor, overflow, root) == ASTRA_ASYNC_CAPACITY);
	astra_async_drop(overflow);
	AstraAsyncTask *second_root = create(NULL, 0);
	assert(astra_async_start(executor, second_root, NULL) == ASTRA_ASYNC_ROOT);
	astra_async_drop(second_root);
	AstraAsyncTask *cold = create(root, 0);
	astra_async_cancel(cold);
	assert(astra_async_start(executor, cold, root) == ASTRA_ASYNC_CANCELLED_COLD);
	astra_async_drop(cold);
	astra_async_begin_shutdown(executor);
	AstraAsyncTask *closed = create(root, 0);
	assert(astra_async_start(executor, closed, root) == ASTRA_ASYNC_CLOSED);
	astra_async_drop(closed);
	assert(pthread_mutex_lock(&lock) == 0);
	proceed = 1;
	assert(pthread_cond_broadcast(&changed) == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	void *error = NULL;
	assert(astra_async_run(executor, root, &error) == ASTRA_ASYNC_CANCELLED && error == NULL);
	assert(atomic_load(&destroyed) == 260);
	assert(astra_async_wake(executor, stale) == 0);
	assert(astra_async_provider_read(executor, stale) == -1);
	astra_async_close(executor);
	astra_async_close(other);
	puts("pool runtime supplement: 256 registrations, capacity/root/association/cold/closed refusal, stale tokens, 260 exact retirements");
	return 0;
}
