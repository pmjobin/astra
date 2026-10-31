/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#ifdef USE_SDK
#include "owners16.h"
#else
typedef struct consumer16_handle consumer16_handle;
typedef struct holder16_handle holder16_handle;
typedef struct owned_item16_handle owned_item16_handle;
typedef struct owned_item16_weak_handle owned_item16_weak_handle;
typedef struct astra_foreign_error { int32_t domain, code; } astra_foreign_error;
int32_t consumer16_create(consumer16_handle **, astra_foreign_error *);
int32_t consumer16_destroy(consumer16_handle **, astra_foreign_error *);
int32_t consumer16_take(consumer16_handle *, owned_item16_handle **, int32_t *, astra_foreign_error *);
int32_t consumer16_relay(consumer16_handle *, owned_item16_handle **, owned_item16_handle **, astra_foreign_error *);
int32_t consumer16_pair(consumer16_handle *, owned_item16_handle **, owned_item16_handle **, int32_t *, astra_foreign_error *);
int32_t consumer16_with_borrow(consumer16_handle *, owned_item16_handle **, owned_item16_handle *, int32_t *, astra_foreign_error *);
int32_t consumer16_watched(consumer16_handle *, owned_item16_handle **, int32_t *, astra_foreign_error *);
int32_t consumer16_preflight(consumer16_handle *, owned_item16_handle **, const uint8_t *, int32_t, int32_t *, astra_foreign_error *);
int32_t consumer16_optional(consumer16_handle *, owned_item16_handle **, int32_t *, astra_foreign_error *);
int32_t holder16_create(owned_item16_handle **, holder16_handle **, astra_foreign_error *);
int32_t holder16_destroy(holder16_handle **, astra_foreign_error *);
int32_t holder16_code(holder16_handle *, int32_t *, astra_foreign_error *);
int32_t owned_item16_create(int32_t, owned_item16_handle **, astra_foreign_error *);
int32_t owned_item16_code(owned_item16_handle *, int32_t *, astra_foreign_error *);
void *owned_item16_root_identity(owned_item16_handle *);
#ifdef EXPECT_SHARED
uint32_t owned_item16_acquire(owned_item16_handle *);
uint32_t owned_item16_release(owned_item16_handle *);
owned_item16_weak_handle *owned_item16_weak(owned_item16_handle *);
owned_item16_handle *owned_item16_weak_upgrade(owned_item16_weak_handle *);
void owned_item16_weak_release(owned_item16_weak_handle *);
#else
int32_t owned_item16_destroy(owned_item16_handle **, astra_foreign_error *);
#endif
#endif
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#c); exit(1); } } while (0)
#define STATUS(c) ((int32_t)UINT32_C(c))
static int retired_count, observed, allocation, deny_allocation;
static consumer16_handle *consumer;
static owned_item16_handle *observer_alias;
void *__real_calloc(size_t, size_t);
void *__wrap_calloc(size_t n, size_t s) { ++allocation; return deny_allocation && allocation == deny_allocation ? NULL : __real_calloc(n,s); }
int32_t owners16_retired(int32_t value) { CHECK(value >= 0); ++retired_count; return 0; }
int32_t owners16_observe(int32_t value) {
	int32_t code = 0; CHECK(value == 47 && observer_alias != NULL); ++observed;
	CHECK(owned_item16_code(observer_alias,&code,NULL) == 0 && code == 47);
#ifdef EXPECT_SHARED
	CHECK(owned_item16_release(observer_alias) == 0); /* no C duty remains */
#else
	CHECK(owned_item16_destroy(&observer_alias,NULL) == STATUS(0x80010001) && observer_alias != NULL);
#endif
	CHECK(consumer16_take(consumer,&observer_alias,&code,NULL) == STATUS(0x80010001) && observer_alias != NULL && code == 0);
	CHECK(owned_item16_code(observer_alias,&code,NULL) == 0 && code == 47);
	return 0;
}
static owned_item16_handle *make(int value) { owned_item16_handle *out = NULL; CHECK(owned_item16_create(value,&out,NULL) == 0 && out); return out; }
static void release(owned_item16_handle **value) {
#ifdef EXPECT_SHARED
	(void)owned_item16_release(*value); *value = NULL;
#else
	CHECK(owned_item16_destroy(value,NULL) == 0 && !*value);
#endif
}
struct worker_state { pthread_mutex_t mutex; pthread_cond_t condition; int ready, finished; owned_item16_handle *item; };
static void *owner_thread(void *argument) {
	struct worker_state *state = argument; owned_item16_handle *item = make(59);
	CHECK(pthread_mutex_lock(&state->mutex) == 0); state->item = item; state->ready = 1; CHECK(pthread_cond_signal(&state->condition) == 0);
	while (!state->finished) { CHECK(pthread_cond_wait(&state->condition,&state->mutex) == 0); }
	CHECK(pthread_mutex_unlock(&state->mutex) == 0); release(&item); return NULL;
}
int main(void) {
	CHECK(consumer16_create(&consumer,NULL) == 0);
	owned_item16_handle *item = make(41), *result = NULL, *alias = item; int32_t code = 99; astra_foreign_error error = {99,99};
	CHECK(consumer16_take(consumer,NULL,&code,&error) == STATUS(0x80004003) && item == alias);
	CHECK(consumer16_take(consumer,&item,NULL,&error) == STATUS(0x80004003) && item == alias);
	CHECK(consumer16_relay(consumer,&item,&item,&error) == STATUS(0x80070057) && item == alias);
	CHECK(consumer16_pair(consumer,&item,&item,&code,&error) == STATUS(0x80070057) && item == alias);
	CHECK(consumer16_pair(consumer,&item,&alias,&code,&error) == STATUS(0x80010001) && item == alias && code == 0);
	uint8_t bytes[] = {1,2,3}; allocation = 0; deny_allocation = 1;
	CHECK(consumer16_preflight(consumer,&item,bytes,3,&code,&error) == STATUS(0x8007000e) && item == alias && retired_count == 0 && code == 0); deny_allocation = 0;
	CHECK(consumer16_preflight(consumer,&item,bytes,-1,&code,&error) == STATUS(0x80070057) && item == alias);
	void *identity = owned_item16_root_identity(item);
	CHECK(consumer16_relay(consumer,&item,&result,&error) == 0 && item == NULL && result == alias && owned_item16_root_identity(result) == identity && retired_count == 0);
	CHECK(consumer16_take(consumer,&result,&code,&error) == 0 && result == NULL && code == 41 && retired_count == 1);
	CHECK(consumer16_optional(consumer,&item,&code,&error) == 0 && item == NULL && code == -7);
	item = make(42); alias = item;
#ifdef EXPECT_SHARED
	CHECK(owned_item16_acquire(item) >= 2);
	CHECK(consumer16_pair(consumer,&item,&alias,&code,&error) == 0 && !item && !alias && code == 84 && retired_count == 2);
	item = make(44); alias = item;
	CHECK(consumer16_with_borrow(consumer,&item,alias,&code,&error) == 0 && !item && code == 88 && retired_count == 3);
#else
	CHECK(consumer16_with_borrow(consumer,&item,alias,&code,&error) == STATUS(0x80010001) && item == alias && code == 0 && retired_count == 1);
	release(&item); CHECK(retired_count == 2); item = make(44); release(&item); CHECK(retired_count == 3);
#endif
	item = make(47); observer_alias = item;
	CHECK(consumer16_watched(consumer,&item,&code,&error) == 0 && !item && code == 47 && observed == 1 && retired_count == 4); observer_alias = NULL;
	item = make(49); alias = item; holder16_handle *holder = NULL; allocation = 0; deny_allocation = 1;
	CHECK(holder16_create(&item,&holder,&error) == STATUS(0x8007000e) && item == alias && !holder && retired_count == 4); deny_allocation = 0;
	allocation = 0; deny_allocation = 2;
	CHECK(holder16_create(&item,&holder,&error) == STATUS(0x8007000e) && !item && !holder && retired_count == 5); deny_allocation = 0;
	item = make(51); CHECK(holder16_create(&item,&holder,&error) == 0 && !item && holder);
	CHECK(holder16_code(holder,&code,&error) == 0 && code == 51);
	CHECK(holder16_destroy(&holder,&error) == 0 && !holder && retired_count == 6);
#ifdef EXPECT_SHARED
	item = make(53); owned_item16_weak_handle *weak = owned_item16_weak(item); CHECK(weak);
	result = owned_item16_weak_upgrade(weak); CHECK(result == item); release(&item);
	CHECK(consumer16_take(consumer,&result,&code,&error) == 0 && !result && code == 53 && retired_count == 7);
	CHECK(owned_item16_weak_upgrade(weak) == NULL); owned_item16_weak_release(weak);
#endif
	struct worker_state state = {.mutex=PTHREAD_MUTEX_INITIALIZER,.condition=PTHREAD_COND_INITIALIZER}; pthread_t worker;
	CHECK(pthread_create(&worker,NULL,owner_thread,&state) == 0); CHECK(pthread_mutex_lock(&state.mutex) == 0);
	while (!state.ready) { CHECK(pthread_cond_wait(&state.condition,&state.mutex) == 0); }
	item = state.item; alias = item;
	CHECK(consumer16_take(consumer,&item,&code,&error) == STATUS(0x8001010e) && item == alias && code == 0);
	state.finished = 1; CHECK(pthread_cond_signal(&state.condition) == 0); CHECK(pthread_mutex_unlock(&state.mutex) == 0); CHECK(pthread_join(worker,NULL) == 0);
	CHECK(pthread_cond_destroy(&state.condition) == 0 && pthread_mutex_destroy(&state.mutex) == 0); item = NULL;
	CHECK(consumer16_destroy(&consumer,NULL) == 0 && !consumer);
	puts("PASS consuming native owners, transfer rollback, identity and reentry"); return 0;
}
