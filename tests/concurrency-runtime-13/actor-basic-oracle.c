// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _GNU_SOURCE
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static int active, proceed, finished, receivers, cooperative;
static int drops[5];
int32_t actor_test_handle(int32_t id) {
	char name[16];
	assert(pthread_getname_np(pthread_self(), name, sizeof(name)) == 0);
	assert(strcmp(name, "astra-actor") == 0);
	assert(id == 0);
	assert(pthread_mutex_lock(&lock) == 0);
	assert(active == 0 && finished == 0 && receivers == 0);
	active = 1;
	assert(pthread_cond_broadcast(&changed) == 0);
	while (!proceed)
		assert(pthread_cond_wait(&changed, &lock) == 0);
	active = 0;
	finished = 1;
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}
int32_t actor_test_message_drop(int32_t id) {
	assert(id >= 0 && id < 5);
	assert(pthread_mutex_lock(&lock) == 0);
	assert(drops[id]++ == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}
int32_t actor_test_receiver_drop(void) {
	assert(pthread_mutex_lock(&lock) == 0);
	assert(active == 0 && finished == 1 && cooperative == 1 && drops[0] == 1 && receivers++ == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}
int32_t actor_test_wait(void) {
	assert(pthread_mutex_lock(&lock) == 0);
	while (!active)
		assert(pthread_cond_wait(&changed, &lock) == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}
int32_t actor_test_continue(void) {
	assert(pthread_mutex_lock(&lock) == 0);
	proceed = 1;
	assert(pthread_cond_broadcast(&changed) == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}
int32_t actor_test_rejected(int32_t id) {
	assert(id >= 0 && id < 5);
	assert(pthread_mutex_lock(&lock) == 0);
	assert(drops[id] == 1);
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}
int32_t actor_test_finish(void) {
	assert(receivers == 1 && finished == 1);
	for (int i = 0; i < 5; ++i)
		assert(drops[i] == 1);
	puts("native Actor: named handler, full/closed consumption, queued cancellation, joined receiver destruction");
	return 0;
}

int32_t actor_test_cooperative(int32_t flag) {
	assert(flag == 1);
	assert(pthread_mutex_lock(&lock) == 0);
	assert(cooperative++ == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	return 0;
}
