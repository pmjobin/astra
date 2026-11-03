/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "virtual.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct State {
	int entries;
	int destroyed;
	int discard;
	int mode;
	int value;
	AstraAsyncTask *child;
	AstraAsyncTask *second;
} State;

static int destroyed;
static int entries;
static int exception_identity;

static void dispose(AstraAsyncTask *task, int discard) {
	State *state = astra_async_data(task);
	state->destroyed++;
	state->discard = discard;
	destroyed++;
}

static AstraAsyncTask *create(AstraAsyncTask *parent, int mode);

static void resume(AstraAsyncTask *task) {
	State *state = astra_async_data(task);
	state->entries++;
	entries++;
	if (astra_async_cancel_requested(task)) {
		if (astra_async_cancel_scope(task)) {
			astra_async_complete(task, ASTRA_ASYNC_CANCELLED, NULL);
		}
		return;
	}
	if (astra_async_pc(task) == 0) {
		astra_async_set_pc(task, 1);
		if (state->mode == 5) {
			AstraAsyncToken token = astra_async_token(task);
			assert(astra_async_wake(astra_async_executor(task), token) && astra_async_wake(astra_async_executor(task), token));
		}
		assert(astra_async_delay(task, state->mode == 5 ? 0 : state->mode == 6 ? 1000
		                                                                       : 2));
		return;
	}
	if ((state->mode == 1 || state->mode == 3 || state->mode == 4) && astra_async_pc(task) == 1) {
		astra_async_set_pc(task, 2);
		assert(astra_async_wait(task, state->child, state->mode == 4) == ASTRA_ASYNC_ADMITTED);
		return;
	}
	if (state->mode == 4 && astra_async_pc(task) == 2) {
		assert(astra_async_release_wait(task, 0) == ASTRA_ASYNC_CANCELLED);
		astra_async_set_pc(task, 3);
		assert(astra_async_wait(task, state->second, 0) == ASTRA_ASYNC_ADMITTED);
		return;
	}
	if (state->mode == 1 || state->mode == 3 || state->mode == 4) {
		AstraAsyncTask *child = astra_async_waited(task);
		State *data = astra_async_data(child);
		state->value = data->value;
		assert(astra_async_release_wait(task, 1) == ASTRA_ASYNC_SUCCESS);
	} else {
		state->value = 42;
	}
	if (state->mode == 3) {
		AstraAsyncTask *overflow = create(task, 0);
		assert(astra_async_start(astra_async_executor(task), overflow, task) == ASTRA_ASYNC_CAPACITY);
		astra_async_drop(overflow);
	}
	astra_async_complete(task, state->mode == 2 ? ASTRA_ASYNC_EXCEPTION : ASTRA_ASYNC_SUCCESS, state->mode == 2 ? &exception_identity : NULL);
}

static AstraAsyncTask *create(AstraAsyncTask *parent, int mode) {
	AstraAsyncTask *task = astra_async_new(sizeof(State), _Alignof(State), resume, dispose, parent);
	*(State *)astra_async_data(task) = (State){.mode = mode};
	return task;
}

static void finish(AstraAsyncExecutor *executor, AstraAsyncTask *root, int expected) {
	assert(astra_async_phase(root) == expected);
	astra_async_begin_shutdown(executor);
	assert(astra_async_shutdown_complete(executor));
	assert(!astra_async_finish_shutdown(executor));
	assert(astra_async_observe_root(executor, root, expected != ASTRA_ASYNC_CANCELLED) == expected);
	assert(astra_async_finish_shutdown(executor));
	astra_async_close(executor);
}

static void cold_and_admission(void) {
	int before = entries;
	AstraAsyncTask *task = create(NULL, 0);
	assert(astra_async_phase(task) == ASTRA_ASYNC_NEW && ((State *)astra_async_data(task))->entries == 0);
	astra_async_drop(task);
	assert(entries == before);
	task = create(NULL, 0);
	astra_async_cancel(task);
	AstraAsyncExecutor *executor = astra_async_open(1);
	assert(astra_async_start(executor, task, NULL) == ASTRA_ASYNC_CANCELLED_COLD);
	astra_async_drop(task);
	astra_async_close(executor);
	assert(astra_async_open(0) == NULL);
}

static void nested_and_manual_time(void) {
	AstraAsyncExecutor *executor = astra_async_open(2);
	AstraAsyncTask *root = create(NULL, 1);
	State *state = astra_async_data(root);
	state->child = create(root, 0);
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	assert(state->entries == 0);
	assert(astra_async_pump(executor, 1) == 1 && state->entries == 1);
	assert(astra_async_pump(executor, 100) == 0);
	assert(astra_async_advance(executor, 1) && astra_async_pump(executor, 100) == 0);
	assert(astra_async_advance(executor, 1) && astra_async_pump(executor, 1) == 1);
	assert(astra_async_pump(executor, 1) == 1);
	assert(astra_async_advance_next(executor));
	assert(astra_async_pump(executor, 2) == 2 && state->value == 42 && state->entries == 3);
	finish(executor, root, ASTRA_ASYNC_SUCCESS);
}

static void retention_and_stale_tokens(void) {
	AstraAsyncExecutor *executor = astra_async_open(1);
	AstraAsyncTask *root = create(NULL, 2);
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	AstraAsyncToken token = astra_async_token(root);
	unsigned char backing = 173;
	assert(astra_async_retain(root, &backing));
	assert(!astra_async_retain(root, &backing));
	assert(astra_async_pump(executor, 1) == 1);
	assert(astra_async_advance_next(executor));
	assert(astra_async_wake(executor, token) && astra_async_wake(executor, token));
	assert(astra_async_pump(executor, 1) == 1);
	assert(astra_async_phase(root) == ASTRA_ASYNC_DRAINING);
	assert(astra_async_provider_read(executor, token) == 173);
	assert(astra_async_observe_release(executor, token));
	assert(!astra_async_observe_release(executor, token));
	assert(astra_async_phase(root) == ASTRA_ASYNC_EXCEPTION && astra_async_exception(root) == &exception_identity);
	astra_async_cancel(root);
	assert(astra_async_phase(root) == ASTRA_ASYNC_EXCEPTION);
	assert(!astra_async_wake(executor, token));
	assert(astra_async_observe_root(executor, root, 1) == ASTRA_ASYNC_EXCEPTION);
	assert(!astra_async_wake(executor, token) && astra_async_provider_read(executor, token) == -1);
	astra_async_begin_shutdown(executor);
	assert(astra_async_finish_shutdown(executor));
	astra_async_close(executor);
	executor = astra_async_open(1);
	root = create(NULL, 0);
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	assert(!astra_async_wake(executor, token));
	astra_async_cancel(root);
	assert(astra_async_pump(executor, 1) == 1);
	finish(executor, root, ASTRA_ASYNC_CANCELLED);
}

static void cancellation_and_capacity(void) {
	AstraAsyncExecutor *executor = astra_async_open(2);
	AstraAsyncTask *root = create(NULL, 1);
	State *state = astra_async_data(root);
	state->child = create(root, 0);
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	assert(astra_async_start(executor, state->child, root) == ASTRA_ASYNC_ADMITTED);
	AstraAsyncTask *overflow = create(root, 0);
	assert(astra_async_start(executor, overflow, root) == ASTRA_ASYNC_CAPACITY && astra_async_phase(overflow) == ASTRA_ASYNC_NEW);
	astra_async_drop(overflow);
	assert(astra_async_pump(executor, 2) == 2);
	unsigned char backing = 91;
	assert(astra_async_retain(state->child, &backing));
	AstraAsyncToken token = astra_async_token(state->child);
	astra_async_cancel(root);
	assert(astra_async_pump(executor, 2) == 2);
	assert(astra_async_phase(root) == ASTRA_ASYNC_DRAINING);
	assert(astra_async_provider_read(executor, token) == 91);
	assert(astra_async_observe_release(executor, token));
	assert(astra_async_pump(executor, 2) >= 1);
	finish(executor, root, ASTRA_ASYNC_CANCELLED);
}

static void exact_association(void) {
	AstraAsyncExecutor *first = astra_async_open(2), *second = astra_async_open(2);
	AstraAsyncTask *root = create(NULL, 0);
	assert(astra_async_start(first, root, NULL) == ASTRA_ASYNC_ADMITTED);
	assert(astra_async_start(second, root, NULL) == ASTRA_ASYNC_ASSOCIATION);
	AstraAsyncTask *wrong = create(root, 0);
	assert(astra_async_start(second, wrong, root) == ASTRA_ASYNC_ASSOCIATION && astra_async_phase(wrong) == ASTRA_ASYNC_NEW);
	astra_async_drop(wrong);
	AstraAsyncTask *other = create(NULL, 0);
	assert(astra_async_start(first, other, NULL) == ASTRA_ASYNC_ROOT && astra_async_phase(other) == ASTRA_ASYNC_NEW);
	astra_async_drop(other);
	for (unsigned guard = 0; guard < 5; guard++) {
		pid_t process = fork();
		assert(process >= 0);
		if (process == 0) {
			void *exception;
			if (guard == 0) {
				astra_async_host_cancel(second, root);
			} else if (guard == 1) {
				astra_async_run(second, root, &exception);
			} else if (guard == 2) {
				astra_async_observe_root(second, root, 0);
			} else if (guard == 3) {
				astra_async_close(first);
			} else {
				astra_async_drop(root);
			}
			_exit(99);
		}
		int status;
		assert(waitpid(process, &status, 0) == process && WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT);
	}
	astra_async_host_cancel(first, root);
	assert(astra_async_pump(first, 1) == 1);
	finish(first, root, ASTRA_ASYNC_CANCELLED);
	astra_async_close(second);
	puts("exact executor association passed; start refusals preserve owners; five fatal guards precede invalidation");
}

static void immediate_coalesced_wakes(void) {
	AstraAsyncExecutor *executor = astra_async_open(1);
	AstraAsyncTask *root = create(NULL, 5);
	State *state = astra_async_data(root);
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	AstraAsyncToken token = astra_async_token(root);
	assert(astra_async_wake(executor, token) && astra_async_wake(executor, token));
	assert(state->entries == 0);
	assert(astra_async_pump(executor, 1) == 1 && state->entries == 1 && astra_async_phase(root) == ASTRA_ASYNC_WAITING);
	assert(astra_async_pump(executor, 1) == 1 && state->entries == 2 && astra_async_phase(root) == ASTRA_ASYNC_SUCCESS && state->value == 42);
	assert(!astra_async_wake(executor, token) && astra_async_pump(executor, 8) == 0);
	finish(executor, root, ASTRA_ASYNC_SUCCESS);
	puts("registration, zero delay, wake during resumption and coalesced pressure passed with exactly two body turns");
}

static void generation_exhaustion(void) {
	AstraAsyncExecutor *executor = astra_async_open(2);
	AstraAsyncTask *root = create(NULL, 3);
	State *state = astra_async_data(root);
	state->child = create(root, 0);
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	astra_async_test_generation(executor, 1, UINT64_MAX - 1);
	assert(astra_async_pump(executor, 1) == 1);
	assert(astra_async_advance_next(executor));
	assert(astra_async_pump(executor, 1) == 1);
	AstraAsyncToken token = astra_async_token(state->child);
	assert(token.generation == UINT64_MAX);
	while (astra_async_phase(root) < ASTRA_ASYNC_SUCCESS) {
		astra_async_pump(executor, 4);
		astra_async_advance_next(executor);
	}
	assert(state->value == 42 && !astra_async_wake(executor, token) && astra_async_provider_read(executor, token) == -1);
	finish(executor, root, ASTRA_ASYNC_SUCCESS);
	puts("token generation final admission and exhaustion passed without wrap or stale access");
}

static void staged_parent_cancellation(void) {
	AstraAsyncExecutor *executor = astra_async_open(40);
	AstraAsyncTask *root = create(NULL, 4);
	State *state = astra_async_data(root);
	state->child = create(root, 0);
	state->second = create(root, 0);
	AstraAsyncTask *children[34];
	assert(astra_async_start(executor, root, NULL) == ASTRA_ASYNC_ADMITTED);
	assert(astra_async_start(executor, state->child, root) == ASTRA_ASYNC_ADMITTED);
	assert(astra_async_start(executor, state->second, root) == ASTRA_ASYNC_ADMITTED);
	for (unsigned i = 0; i < 34; i++) {
		children[i] = create(state->child, 6);
		assert(astra_async_start(executor, children[i], state->child) == ASTRA_ASYNC_ADMITTED);
	}
	assert(astra_async_pump(executor, 37) == 37);
	unsigned char *first = (unsigned char *)&((State *)astra_async_data(children[0]))->value;
	unsigned char *last = (unsigned char *)&((State *)astra_async_data(children[33]))->value;
	*first = 73;
	*last = 91;
	assert(astra_async_retain(children[0], first) && astra_async_retain(children[33], last));
	AstraAsyncToken first_token = astra_async_token(children[0]), last_token = astra_async_token(children[33]);
	astra_async_cancel(state->child);
	assert(astra_async_pump(executor, 1) == 1);
	assert(astra_async_phase(state->child) == ASTRA_ASYNC_DRAINING && astra_async_phase(root) != ASTRA_ASYNC_CANCELLED);
	astra_async_advance_next(executor);
	for (unsigned i = 0; i < 20; i++) {
		astra_async_pump(executor, 8);
	}
	assert(astra_async_phase(state->second) == ASTRA_ASYNC_SUCCESS && ((State *)astra_async_data(state->second))->value == 42);
	assert(astra_async_phase(root) == ASTRA_ASYNC_WAITING && astra_async_provider_read(executor, first_token) == 73 && astra_async_provider_read(executor, last_token) == 91);
	assert(astra_async_observe_release(executor, last_token));
	astra_async_pump(executor, 8);
	assert(astra_async_phase(root) == ASTRA_ASYNC_WAITING);
	assert(astra_async_observe_release(executor, first_token));
	for (unsigned turns = 0; astra_async_phase(root) < ASTRA_ASYNC_SUCCESS; turns++) {
		assert(turns < 40);
		astra_async_pump(executor, 8);
	}
	assert(state->value == 42 && !astra_async_wake(executor, first_token) && !astra_async_wake(executor, last_token));
	finish(executor, root, ASTRA_ASYNC_SUCCESS);
	puts("staged parent-only cancellation passed: 34 descendants, two actual retained backings and useful unrelated completion");
}

int main(void) {
	cold_and_admission();
	nested_and_manual_time();
	retention_and_stale_tokens();
	cancellation_and_capacity();
	assert(destroyed == 9);
	exact_association();
	immediate_coalesced_wakes();
	generation_exhaustion();
	staged_parent_cancellation();
	printf("virtual-runtime protocol controls passed; entries=%d destroyed=%d\n", entries, destroyed);
	return 0;
}
