/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#ifdef USE_SDK
#include "objects16.h"
#else
typedef struct service16_handle service16_handle;
typedef struct item16_handle item16_handle;
typedef struct item16_weak_handle item16_weak_handle;
typedef struct astra_foreign_error { int32_t domain, code; } astra_foreign_error;
int32_t service16_create(int32_t, service16_handle **, astra_foreign_error *);
int32_t service16_destroy(service16_handle **, astra_foreign_error *);
int32_t service16_create_item(service16_handle *, int32_t, item16_handle **, astra_foreign_error *);
int32_t service16_maybe(service16_handle *, bool, int32_t, item16_handle **, astra_foreign_error *);
int32_t service16_inspect(service16_handle *, item16_handle *, int32_t *, astra_foreign_error *);
int32_t service16_required(service16_handle *, item16_handle *, int32_t *, astra_foreign_error *);
int32_t service16_optional(service16_handle *, item16_handle *, int32_t *, astra_foreign_error *);
int32_t service16_watched(service16_handle *, item16_handle *, int32_t *, astra_foreign_error *);
int32_t item16_create(int32_t, item16_handle **, astra_foreign_error *);
int32_t item16_code(item16_handle *, int32_t *, astra_foreign_error *);
int32_t item16_update(item16_handle *, int32_t, astra_foreign_error *);
void *item16_root_identity(item16_handle *);
#ifdef EXPECT_SHARED
int32_t service16_duplicate(service16_handle *, item16_handle *, item16_handle **, astra_foreign_error *);
uint32_t item16_acquire(item16_handle *);
uint32_t item16_release(item16_handle *);
item16_weak_handle *item16_weak(item16_handle *);
item16_handle *item16_weak_upgrade(item16_weak_handle *);
void item16_weak_release(item16_weak_handle *);
#else
int32_t item16_destroy(item16_handle **, astra_foreign_error *);
#endif
#endif
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); exit(1); } } while (0)
#define STATUS(c) ((int32_t)UINT32_C(c))
static service16_handle *service;
static item16_handle *watched;
static int allocations, deny_allocation, service_retired, item_retired, observations;
void *__real_calloc(size_t, size_t);
void *__wrap_calloc(size_t count, size_t size) {
	++allocations;
	return deny_allocation != 0 && allocations == deny_allocation ? NULL : __real_calloc(count, size);
}
int32_t objects16_retired(int32_t code) { if (code == -1) { ++service_retired; } else { ++item_retired; } return 0; }
int32_t objects16_observe(int32_t code) {
	CHECK(code == 42 && watched != NULL); ++observations;
	CHECK(service16_destroy(&service, NULL) == STATUS(0x80010001) && service != NULL);
	CHECK(item16_update(watched, 43, NULL) == 0);
#ifdef EXPECT_SHARED
	(void)item16_release(watched); watched = NULL;
#else
	CHECK(item16_destroy(&watched, NULL) == STATUS(0x80010001) && watched != NULL);
#endif
	return 0;
}
static void release_item(item16_handle **value) {
#ifdef EXPECT_SHARED
	(void)item16_release(*value); *value = NULL;
#else
	CHECK(item16_destroy(value, NULL) == 0 && *value == NULL);
#endif
}
struct worker_state { pthread_mutex_t mutex; pthread_cond_t condition; bool ready, finished; item16_handle *owner;
#ifdef EXPECT_SHARED
	item16_weak_handle *weak;
#endif
};
static void *foreign_owner_thread(void *argument) {
	struct worker_state *state = argument; item16_handle *owner = NULL;
	CHECK(item16_create(90, &owner, NULL) == 0);
	CHECK(pthread_mutex_lock(&state->mutex) == 0); state->owner = owner; state->ready = true; CHECK(pthread_cond_signal(&state->condition) == 0);
#ifdef EXPECT_SHARED
	state->weak = item16_weak(owner); CHECK(state->weak != NULL);
#endif
	while (!state->finished) { CHECK(pthread_cond_wait(&state->condition, &state->mutex) == 0); }
	CHECK(pthread_mutex_unlock(&state->mutex) == 0);
	int32_t code = 0; CHECK(item16_code(owner, &code, NULL) == 0 && code == 90); release_item(&owner);
#ifdef EXPECT_SHARED
	CHECK(item16_weak_upgrade(state->weak) == NULL); item16_weak_release(state->weak);
#endif
	return NULL;
}
int main(void) {
	astra_foreign_error error = {99, 99}; CHECK(service16_create(7, &service, &error) == 0);
	item16_handle *child = NULL; int32_t code = 99;
	CHECK(service16_maybe(service, false, 123, &child, &error) == 0 && child == NULL && error.code == 0);
	CHECK(service16_optional(service, NULL, &code, &error) == 0 && code == -99);
	CHECK(service16_inspect(service, NULL, &code, &error) == STATUS(0x80004003) && code == 0);
	CHECK(service16_create_item(service, 35, NULL, &error) == STATUS(0x80004003));
	allocations = 0; deny_allocation = 2; /* native root succeeds; first wrapper allocation fails */
	CHECK(service16_create_item(service, 35, &child, &error) == STATUS(0x8007000e));
	CHECK(child == NULL && item_retired == 1 && error.code == STATUS(0x8007000e)); deny_allocation = 0;
	CHECK(service16_create_item(service, 35, &child, &error) == 0 && child != NULL);
	CHECK(item16_code(child, &code, &error) == 0 && code == 42);
	CHECK(service16_inspect(service, child, &code, &error) == 0 && code == 42);
	CHECK(service16_required(service, child, &code, &error) == 0 && code == 42);
	CHECK(item16_root_identity(child) != NULL && item16_root_identity(child) != (void *)child);
#ifdef EXPECT_SHARED
	item16_handle *copy = NULL; CHECK(service16_duplicate(service, child, &copy, &error) == 0 && copy == child);
	release_item(&copy); CHECK(item_retired == 1);
#endif
	watched = child; CHECK(service16_watched(service, child, &code, &error) == 0 && code == 43 && observations == 1);
#ifdef EXPECT_SHARED
	CHECK(watched == NULL && item_retired == 2); child = NULL;
#else
	CHECK(watched == child && item_retired == 1); release_item(&child); watched = NULL; CHECK(item_retired == 2);
#endif
	struct worker_state state = {.mutex = PTHREAD_MUTEX_INITIALIZER, .condition = PTHREAD_COND_INITIALIZER}; pthread_t worker;
	CHECK(pthread_create(&worker, NULL, foreign_owner_thread, &state) == 0); CHECK(pthread_mutex_lock(&state.mutex) == 0);
	while (!state.ready) { CHECK(pthread_cond_wait(&state.condition, &state.mutex) == 0); }
	CHECK(service16_inspect(service, state.owner, &code, &error) == STATUS(0x8001010e)); CHECK(code == 0 && error.code == STATUS(0x8001010e));
#ifdef EXPECT_SHARED
	CHECK(item16_acquire(state.owner) == 0 && item16_release(state.owner) == 0);
	CHECK(item16_weak_upgrade(state.weak) == NULL); item16_weak_release(state.weak); /* refusal leaves the original weak duty intact */
#endif
	state.finished = true; CHECK(pthread_cond_signal(&state.condition) == 0); CHECK(pthread_mutex_unlock(&state.mutex) == 0); CHECK(pthread_join(worker, NULL) == 0);
	CHECK(pthread_cond_destroy(&state.condition) == 0 && pthread_mutex_destroy(&state.mutex) == 0 && item_retired == 3);
	CHECK(service16_maybe(service, true, 1, &child, &error) == 0 && child != NULL);
	CHECK(service16_destroy(&service, &error) == 0 && service == NULL && service_retired == 1);
	CHECK(item16_code(child, &code, &error) == 0 && code == 8); release_item(&child); CHECK(item_retired == 4);
	puts("PASS declaration-derived nominal native handles, owned results, borrow lifetime and context");
	return 0;
}
