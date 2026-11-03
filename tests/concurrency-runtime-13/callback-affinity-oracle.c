// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _POSIX_C_SOURCE 200809L
#include "../../lib/runtime/runtime/threads-13.h"
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>

struct callback {
	astra_thread_callback code;
	void *context, *token;
	pthread_t parent, worker;
	int entered, returned, retired, dropped;
};
static struct callback registrations[4];
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static int entered, local_drops, ledger_drops;
void *__real_astra_thread_register(astra_thread_callback, void *, int32_t);
int32_t __real_astra_thread_retire(void *);

static int32_t foreign_entry(void *opaque, int32_t value) {
	struct callback *callback = opaque;
	assert(callback == &registrations[value - 1] && callback->code && callback->context);
	assert(!pthread_equal(callback->parent, pthread_self()));
	assert(pthread_mutex_lock(&lock) == 0);
	callback->worker = pthread_self();
	assert(callback->entered++ == 0);
	++entered;
	assert(pthread_cond_broadcast(&changed) == 0);
	while (entered != 4)
		assert(pthread_cond_wait(&changed, &lock) == 0);
	assert(callback->dropped == 0 && callback->retired == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	int32_t result = callback->code(callback->context, value);
	assert(result == (value == 2 ? -7 : value));
	assert(pthread_mutex_lock(&lock) == 0);
	assert(callback->dropped == 0 && callback->returned++ == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	return result;
}

void *__wrap_astra_thread_register(astra_thread_callback code, void *context, int32_t value) {
	assert(value >= 1 && value <= 4 && code && context);
	struct callback *callback = &registrations[value - 1];
	assert(callback->code == NULL);
	callback->code = code;
	callback->context = context;
	callback->parent = pthread_self();
	callback->token = __real_astra_thread_register(foreign_entry, callback, value);
	assert(callback->token);
	return callback->token;
}

int32_t __wrap_astra_thread_retire(void *token) {
	int result = __real_astra_thread_retire(token);
	assert(result == 1);
	assert(pthread_mutex_lock(&lock) == 0);
	int found = 0;
	for (int i = 0; i < 4; ++i)
		if (registrations[i].token == token) {
			assert(registrations[i].returned == 1 && registrations[i].retired++ == 0);
			found = 1;
		}
	assert(found);
	assert(pthread_mutex_unlock(&lock) == 0);
	return result;
}

int32_t callback_capture_drop(int32_t id) {
	assert(id >= 0 && id < 4 && registrations[id].retired == 1 && registrations[id].dropped++ == 0);
	return 0;
}

int32_t callback_local_drop(void) {
	assert(local_drops++ == 0);
	return 0;
}

int32_t callback_ledger_drop(void) {
	for (int i = 0; i < 4; ++i)
		assert(registrations[i].retired == 1 && registrations[i].dropped == 1);
	assert(ledger_drops++ == 0);
	return 0;
}

int32_t callback_affinity_finish(void) {
	assert(entered == 4 && local_drops == 1 && ledger_drops == 1);
	for (int i = 0; i < 4; ++i)
		for (int j = i + 1; j < 4; ++j)
			assert(!pthread_equal(registrations[i].worker, registrations[j].worker));
	puts("C callback boundary: four retained contexts, foreign worker entry, caught native error, joined retirement; local ThreadBound callback preserved");
	return 0;
}
