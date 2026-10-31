/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <pthread.h>

#ifdef USE_SDK
#include "scalar16.h"
#else
/* Independent C declarations: these do not read the generated SDK. */
typedef struct scalar16_handle scalar16_handle;
typedef struct scalar16_weak_handle scalar16_weak_handle;
typedef struct astra_foreign_error { int32_t domain; int32_t code; } astra_foreign_error;
int32_t scalar16_start(int64_t, double, scalar16_handle **, astra_foreign_error *);
int32_t scalar16_add(scalar16_handle *, int64_t, int64_t *, astra_foreign_error *);
int32_t scalar16_bits(scalar16_handle *, uint32_t, uint32_t *, astra_foreign_error *);
int32_t scalar16_wide(scalar16_handle *, uint64_t, uint64_t *, astra_foreign_error *);
int32_t scalar16_narrow(scalar16_handle *, float, float *, astra_foreign_error *);
int32_t scalar16_floating(scalar16_handle *, double, double *, astra_foreign_error *);
int32_t scalar16_flag(scalar16_handle *, bool, bool *, astra_foreign_error *);
int32_t scalar16_select(scalar16_handle *, int32_t, int32_t, bool, int32_t *, astra_foreign_error *);
int32_t scalar16_weigh(scalar16_handle *, double, double, double *, astra_foreign_error *);
int32_t scalar16_get_gain(scalar16_handle *, double *, astra_foreign_error *);
void *scalar16_root_identity(scalar16_handle *);
#ifdef EXPECT_SHARED
uint32_t scalar16_acquire(scalar16_handle *);
uint32_t scalar16_release(scalar16_handle *);
scalar16_weak_handle *scalar16_weak(scalar16_handle *);
scalar16_handle *scalar16_weak_upgrade(scalar16_weak_handle *);
void scalar16_weak_release(scalar16_weak_handle *);
#else
int32_t scalar16_destroy(scalar16_handle **, astra_foreign_error *);
#endif
#endif

#define CHECK(condition) do { if (!(condition)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); exit(1); } } while (0)
static int created, destroyed, allocations, deny_allocation;
void *__real_calloc(size_t, size_t);
void *__wrap_calloc(size_t count, size_t size) {
	++allocations;
	return deny_allocation != 0 && allocations == deny_allocation ? NULL : __real_calloc(count, size);
}
int32_t scalar16_born(int32_t value) { CHECK(value == 1); ++created; return 0; }
int32_t scalar16_retired(int32_t value) { CHECK(value == 1); ++destroyed; return 0; }
#ifdef _WIN32
extern uint64_t astra_foreign14_thread_identity(void);
#endif

static void *wrong_thread(void *argument) {
	int64_t value = 99;
	astra_foreign_error error = { 99, 99 };
	CHECK(scalar16_add(argument, 5, &value, &error) == (int32_t)UINT32_C(0x8001010e));
	CHECK(value == 0 && error.code == (int32_t)UINT32_C(0x8001010e));
	return NULL;
}

int main(void) {
#ifdef _WIN32
	/* MinGW emulated TLS allocates during first use. Bootstrap the runtime
	 * before injecting failure into native root/wrapper allocations. */
	CHECK(astra_foreign14_thread_identity() != 0);
#endif
	scalar16_handle *owner = NULL;
	astra_foreign_error error = { 99, 99 };
	for (int failure = 1; failure <= 2; ++failure) {
		allocations = 0; deny_allocation = failure;
		CHECK(scalar16_start(INT64_C(9000000000), 1.5, &owner, &error) == (int32_t)UINT32_C(0x8007000e));
		CHECK(owner == NULL && error.domain == 0 && error.code == (int32_t)UINT32_C(0x8007000e));
		CHECK(created == failure - 1 && destroyed == failure - 1);
	}
	deny_allocation = 0;
	CHECK(scalar16_start(1, 2, NULL, &error) == (int32_t)UINT32_C(0x80004003));
	CHECK(created == 1 && destroyed == 1);
	CHECK(scalar16_start(INT64_C(9000000000), 1.5, &owner, &error) == 0);
	CHECK(owner != NULL && created == 2 && destroyed == 1 && error.domain == 0 && error.code == 0);
	CHECK(scalar16_root_identity(owner) != NULL && scalar16_root_identity(owner) != (void *)owner);
	int64_t total = 0; uint64_t wide = 0; uint32_t bits = 0;
	float small = 0; double large = 0; bool flag = false; int32_t selected = 0;
	CHECK(scalar16_add(owner, -17, &total, NULL) == 0 && total == INT64_C(8999999983));
	CHECK(scalar16_bits(owner, UINT32_MAX, &bits, &error) == 0 && bits == UINT32_MAX);
	CHECK(scalar16_wide(owner, UINT64_MAX, &wide, &error) == 0 && wide == UINT64_MAX);
	CHECK(scalar16_narrow(owner, -0.0f, &small, &error) == 0 && signbit(small));
	CHECK(scalar16_floating(owner, NAN, &large, &error) == 0 && isnan(large));
	CHECK(scalar16_flag(owner, true, &flag, &error) == 0 && !flag);
	CHECK(scalar16_flag(owner, false, &flag, &error) == 0 && flag);
	CHECK(scalar16_select(owner, INT32_MIN, INT32_MAX, true, &selected, &error) == 0 && selected == INT32_MIN);
	CHECK(scalar16_select(owner, INT32_MIN, INT32_MAX, false, &selected, &error) == 0 && selected == INT32_MAX);
	CHECK(scalar16_weigh(owner, 2.5, 3.0, &large, &error) == 0 && large == 7.0);
	CHECK(scalar16_get_gain(owner, &large, &error) == 0 && large == 4.0);
	pthread_t worker; CHECK(pthread_create(&worker, NULL, wrong_thread, owner) == 0); CHECK(pthread_join(worker, NULL) == 0);
	CHECK(scalar16_add(owner, 0, &total, &error) == 0 && total == INT64_C(8999999983));
#ifdef EXPECT_SHARED
	scalar16_weak_handle *weak = scalar16_weak(owner); CHECK(weak != NULL);
	scalar16_handle *copy = scalar16_weak_upgrade(weak); CHECK(copy == owner);
	(void)scalar16_release(owner); CHECK(destroyed == 1);
	CHECK(scalar16_get_gain(copy, &large, &error) == 0 && large == 4.0);
	(void)scalar16_release(copy); CHECK(destroyed == 2);
	CHECK(scalar16_weak_upgrade(weak) == NULL); scalar16_weak_release(weak);
#else
	CHECK(scalar16_destroy(&owner, &error) == 0 && owner == NULL && destroyed == 2);
	CHECK(scalar16_destroy(&owner, &error) == 0 && destroyed == 2);
#endif
	CHECK(created == 2 && destroyed == 2);
	puts("PASS declaration-derived scalar native members, typed C ABI, context and exact lifetime");
	return 0;
}
