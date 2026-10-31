/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#ifdef USE_SDK
#include "bytes16.h"
#else
typedef struct bytes16_handle bytes16_handle;
typedef struct astra_foreign_error { int32_t domain, code; } astra_foreign_error;
int32_t bytes16_create(int32_t, bytes16_handle **, astra_foreign_error *);
int32_t bytes16_transform(bytes16_handle *, const uint8_t *, int32_t, uint8_t *, int32_t, int32_t *, astra_foreign_error *);
int32_t bytes16_digest(bytes16_handle *, const uint8_t *, int32_t, int32_t *, astra_foreign_error *);
int32_t bytes16_scrub(bytes16_handle *, const uint8_t *, int32_t, int32_t *, astra_foreign_error *);
int32_t bytes16_mutate(bytes16_handle *, uint8_t *, int32_t, int32_t *, astra_foreign_error *);
int32_t bytes16_partial(bytes16_handle *, uint8_t *, int32_t, int32_t *, astra_foreign_error *);
int32_t bytes16_nested(bytes16_handle *, int32_t *, astra_foreign_error *);
int32_t bytes16_snapshot(bytes16_handle *, const uint8_t *, int32_t, uint8_t **, int32_t *, astra_foreign_error *);
int32_t bytes16_bytes_release(uint8_t **, int32_t *, astra_foreign_error *);
int32_t bytes16_get_processed(bytes16_handle *, int32_t *, astra_foreign_error *);
#ifdef EXPECT_SHARED
uint32_t bytes16_release(bytes16_handle *);
#else
int32_t bytes16_destroy(bytes16_handle **, astra_foreign_error *);
#endif
#endif
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); exit(1); } } while (0)
#define STATUS(c) ((int32_t)UINT32_C(c))
static bytes16_handle *owner;
static bytes16_handle *retiring_view;
static int destroyed, allocations, deny_allocation, nested_calls;
void *__real_calloc(size_t, size_t);
void *__wrap_calloc(size_t count, size_t size) {
	++allocations;
	return deny_allocation != 0 && allocations == deny_allocation ? NULL : __real_calloc(count, size);
}
int32_t bytes16_retired(int32_t mask) {
	CHECK(mask == 37); ++destroyed;
	if (retiring_view != NULL) {
		int32_t output = 99; astra_foreign_error error = {99, 99};
		CHECK(bytes16_get_processed(retiring_view, &output, &error) == STATUS(0x8000ffff));
		CHECK(output == 0 && error.code == STATUS(0x8000ffff));
	}
	return 0;
}
int32_t bytes16_reenter(int32_t mask) {
	CHECK(mask == 37 && destroyed == 0); ++nested_calls;
#ifdef EXPECT_SHARED
	retiring_view = owner;
	(void)bytes16_release(owner); /* retire the caller's last strong during this call */
#else
	CHECK(bytes16_destroy(&owner, NULL) == STATUS(0x80010001));
	CHECK(owner != NULL && destroyed == 0);
#endif
	int32_t calls = -1;
	CHECK(bytes16_get_processed(owner, &calls, NULL) == 0 && calls == 3);
#ifdef EXPECT_SHARED
	owner = NULL;
#endif
	return mask + 1;
}
static void *wrong_thread(void *argument) {
	uint8_t output[4] = {91, 92, 93, 94}; int32_t count = 77;
	CHECK(bytes16_transform(argument, (const uint8_t *)"test", 4, output, 4, &count, NULL) == STATUS(0x8001010e));
	CHECK(count == 0 && output[0] == 91 && output[3] == 94);
	return NULL;
}
int main(void) {
	astra_foreign_error error = {99, 99};
	CHECK(bytes16_create(37, &owner, &error) == 0 && owner != NULL);
	const uint8_t input[] = {0, 1, 127, 128, 255};
	uint8_t output[7]; memset(output, 0xa5, sizeof output); int32_t count = 99, calls = -1;
	for (int failure = 1; failure <= 2; ++failure) {
		allocations = 0; deny_allocation = failure;
		CHECK(bytes16_transform(owner, input, 5, output, 7, &count, &error) == STATUS(0x8007000e));
		CHECK(count == 0 && error.domain == 0 && error.code == STATUS(0x8007000e));
		for (int i = 0; i < 7; ++i) { CHECK(output[i] == 0xa5); }
	}
	deny_allocation = 0;
	CHECK(bytes16_get_processed(owner, &calls, NULL) == 0 && calls == 0);
	CHECK(bytes16_transform(owner, input, -1, output, 7, &count, &error) == STATUS(0x80070057));
	CHECK(bytes16_transform(owner, input, 5, output, -1, &count, &error) == STATUS(0x80070057));
	CHECK(bytes16_transform(owner, NULL, 1, output, 7, &count, &error) == STATUS(0x80004003));
	CHECK(bytes16_transform(owner, input, 5, NULL, 7, &count, &error) == STATUS(0x80004003));
	CHECK(bytes16_transform(owner, input, 5, output, 7, NULL, &error) == STATUS(0x80004003));
	CHECK(bytes16_transform(owner, input, 5, output, 4, &count, &error) == STATUS(0x8000ffff));
	CHECK(count == 0 && error.code == STATUS(0x8000ffff));
	for (int i = 0; i < 7; ++i) { CHECK(output[i] == 0xa5); }
	CHECK(bytes16_transform(owner, input, 5, output, 7, &count, &error) == 0 && count == 5);
	for (int i = 0; i < 5; ++i) { CHECK(output[i] == (uint8_t)(input[i] ^ 37)); }
	CHECK(output[5] == 0xa5 && output[6] == 0xa5);
	CHECK(bytes16_transform(owner, NULL, 0, NULL, 0, &count, &error) == 0 && count == 0);
	uint8_t alias[] = {9, 8, 7, 6};
	CHECK(bytes16_transform(owner, alias, 4, alias, 4, &count, &error) == 0 && count == 4);
	CHECK(alias[0] == (9 ^ 37) && alias[3] == (6 ^ 37));
	CHECK(bytes16_digest(owner, input, 5, &count, &error) == 0 && count == 516);
	CHECK(bytes16_digest(owner, NULL, 0, &count, &error) == 0 && count == 0);
	CHECK(bytes16_scrub(owner, input, 5, &count, &error) == 0 && count == 17 && input[0] == 0 && input[4] == 255);
	uint8_t mutation[] = {4, 5, 6};
	CHECK(bytes16_mutate(owner, mutation, 3, &count, &error) == 0 && count == 3);
	CHECK(mutation[0] == 5 && mutation[2] == 7);
	CHECK(bytes16_partial(owner, output, 7, &count, &error) == STATUS(0x8000ffff) && count == 0);
	CHECK(output[0] == 37 && output[5] == 0xa5);
	uint8_t *snapshot = NULL; int32_t snapshot_length = -1;
	CHECK(bytes16_snapshot(owner, input, 5, &snapshot, NULL, &error) == STATUS(0x80004003));
	CHECK(snapshot == NULL);
	CHECK(bytes16_snapshot(owner, NULL, 5, &snapshot, &snapshot_length, &error) == STATUS(0x80004003));
	CHECK(snapshot == NULL && snapshot_length == 0);
	CHECK(bytes16_snapshot(owner, input, 5, &snapshot, &snapshot_length, &error) == 0 && snapshot_length == 5);
	for (int i = 0; i < 5; ++i) { CHECK(snapshot[i] == (uint8_t)(input[i] ^ 37)); }
	uint8_t *empty = NULL; int32_t empty_length = -1;
	CHECK(bytes16_snapshot(owner, input, 0, &empty, &empty_length, &error) == 0 && empty != NULL && empty_length == 0);
	CHECK(bytes16_bytes_release(&empty, &empty_length, &error) == 0 && empty == NULL && empty_length == 0);
	pthread_t worker; CHECK(pthread_create(&worker, NULL, wrong_thread, owner) == 0); CHECK(pthread_join(worker, NULL) == 0);
	CHECK(bytes16_nested(owner, &count, &error) == 0 && count == 38 && nested_calls == 1);
#ifdef EXPECT_SHARED
	CHECK(owner == NULL && destroyed == 1);
#else
	CHECK(destroyed == 0);
	CHECK(bytes16_get_processed(owner, &calls, NULL) == 0 && calls == 3);
	retiring_view = owner;
	CHECK(bytes16_destroy(&owner, &error) == 0 && owner == NULL);
#endif
	CHECK(destroyed == 1);
	CHECK(snapshot_length == 5 && snapshot[2] == (127 ^ 37)); /* independent of root retirement */
	CHECK(bytes16_bytes_release(&snapshot, NULL, &error) == STATUS(0x80004003) && snapshot != NULL);
	CHECK(bytes16_bytes_release(&snapshot, &snapshot_length, &error) == 0 && snapshot == NULL && snapshot_length == 0);
	CHECK(bytes16_bytes_release(&snapshot, &snapshot_length, &error) == 0);
	puts("PASS declaration-derived counted bytes, staged outputs, allocation rollback and active receiver lifetime");
	return 0;
}
