/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef USE_SDK
#include "text16.h"
#else
typedef struct text16_handle text16_handle;
typedef struct astra_foreign_error { int32_t domain, code; } astra_foreign_error;
int32_t text16_create(int32_t, const char *, int32_t, text16_handle **, astra_foreign_error *);
int32_t text16_measure(text16_handle *, const char *, int32_t, const char *, int32_t, int32_t *, astra_foreign_error *);
int32_t text16_get_label(text16_handle *, char **, int32_t *, astra_foreign_error *);
int32_t text16_constant(text16_handle *, char **, int32_t *, astra_foreign_error *);
int32_t text16_empty(text16_handle *, char **, int32_t *, astra_foreign_error *);
int32_t text16_terminated_length(text16_handle *, const char *, int32_t, int32_t *, astra_foreign_error *);
int32_t text16_terminated(text16_handle *, char **, int32_t *, astra_foreign_error *);
int32_t text16_forbidden_nul(text16_handle *, char **, int32_t *, astra_foreign_error *);
int32_t text16_terminated_empty(text16_handle *, char **, int32_t *, astra_foreign_error *);
int32_t text16_get_processed(text16_handle *, int32_t *, astra_foreign_error *);
int32_t text16_text_release(char **, int32_t *, astra_foreign_error *);
#ifdef EXPECT_SHARED
uint32_t text16_release(text16_handle *);
#else
int32_t text16_destroy(text16_handle **, astra_foreign_error *);
#endif
#endif
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); exit(1); } } while (0)
#define STATUS(c) ((int32_t)UINT32_C(c))
static int allocations, deny_allocation, retired;
void *__real_calloc(size_t, size_t);
void *__wrap_calloc(size_t count, size_t size) {
	++allocations;
	return deny_allocation != 0 && allocations == deny_allocation ? NULL : __real_calloc(count, size);
}
int32_t text16_retired(int32_t tag) { CHECK(tag == 13); ++retired; return 0; }
int main(void) {
	text16_handle *owner = NULL; astra_foreign_error error = {99, 99};
	char initial[] = {'A', '\0', (char)0xc3, (char)0xa9};
	CHECK(text16_create(13, initial, 4, &owner, &error) == 0 && owner != NULL);
	memset(initial, 'x', sizeof initial);
	int32_t count = 99, calls = -1;
	const char valid[] = {(char)0xf0, (char)0x9f, (char)0x96, (char)0xa4, '\0', 'Z'};
	for (int failure = 1; failure <= 2; ++failure) {
		allocations = 0; deny_allocation = failure;
		CHECK(text16_measure(owner, valid, 6, "test", 4, &count, &error) == STATUS(0x8007000e));
		CHECK(count == 0 && error.code == STATUS(0x8007000e));
	}
	deny_allocation = 0;
	CHECK(text16_get_processed(owner, &calls, NULL) == 0 && calls == 0);
	const unsigned char invalid[][4] = {{0xc0, 0x80}, {0xe0, 0x80, 0x80}, {0xed, 0xa0, 0x80}, {0xf4, 0x90, 0x80, 0x80}, {0xf0, 0x9f, 0x96}, {0x80}, {0xff}};
	const int lengths[] = {2, 3, 3, 4, 3, 1, 1};
	for (size_t i = 0; i < sizeof lengths / sizeof *lengths; ++i) {
		CHECK(text16_measure(owner, (const char *)invalid[i], lengths[i], "", 0, &count, &error) == STATUS(0x80070459));
		CHECK(count == 0 && error.domain == 0 && error.code == STATUS(0x80070459));
	}
	CHECK(text16_get_processed(owner, &calls, NULL) == 0 && calls == 0);
	CHECK(text16_measure(owner, NULL, 1, "", 0, &count, &error) == STATUS(0x80004003));
	CHECK(text16_measure(owner, "", -1, "", 0, &count, &error) == STATUS(0x80070057));
	CHECK(text16_measure(owner, valid, 6, "test", 4, &count, &error) == 0 && count == 23);
	CHECK(text16_measure(owner, NULL, 0, NULL, 0, &count, &error) == 0 && count == 13);
	char *snapshot = NULL; int32_t length = -1;
	allocations = 0; deny_allocation = 1;
	CHECK(text16_get_label(owner, &snapshot, &length, &error) == STATUS(0x8007000e));
	CHECK(snapshot == NULL && length == 0 && error.code == STATUS(0x8007000e));
	deny_allocation = 0;
	CHECK(text16_get_label(owner, &snapshot, &length, &error) == 0 && snapshot != NULL && length == 4);
	const unsigned char expected[] = {'A', 0, 0xc3, 0xa9}; CHECK(memcmp(snapshot, expected, 4) == 0);
	char *constant = NULL; int32_t constant_length = -1;
	CHECK(text16_constant(owner, &constant, &constant_length, NULL) == 0 && constant_length == 7);
	const unsigned char literal[] = {'h', 0xc3, 0xa9, 0, 'l', 'l', 'o'}; CHECK(memcmp(constant, literal, 7) == 0);
	CHECK(text16_text_release(&constant, &constant_length, NULL) == 0 && constant == NULL && constant_length == 0);
	CHECK(text16_empty(owner, &constant, &constant_length, NULL) == 0 && constant != NULL && constant_length == 0);
	CHECK(text16_text_release(&constant, &constant_length, NULL) == 0);
	CHECK(text16_terminated_length(owner, "caf\xc3\xa9", 7, &count, &error) == 0 && count == 12);
	CHECK(text16_terminated_length(owner, NULL, 7, &count, &error) == 0 && count == 7);
	CHECK(text16_terminated_length(owner, "\xc0\x80", 7, &count, &error) == STATUS(0x80070459) && count == 0);
	CHECK(text16_terminated(owner, &constant, &constant_length, &error) == 0 && constant_length == 5);
	CHECK(strcmp(constant, "caf\xc3\xa9") == 0 && constant[5] == 0);
	CHECK(text16_text_release(&constant, &constant_length, NULL) == 0);
	CHECK(text16_forbidden_nul(owner, &constant, &constant_length, &error) == STATUS(0x80070057));
	CHECK(constant == NULL && constant_length == 0 && error.code == STATUS(0x80070057));
	CHECK(text16_terminated_empty(owner, &constant, &constant_length, &error) == 0 && constant != NULL && constant_length == 0 && constant[0] == 0);
	CHECK(text16_text_release(&constant, &constant_length, NULL) == 0);
#ifdef EXPECT_SHARED
	(void)text16_release(owner);
#else
	CHECK(text16_destroy(&owner, &error) == 0 && owner == NULL);
#endif
	CHECK(retired == 1 && length == 4 && memcmp(snapshot, expected, 4) == 0);
	CHECK(text16_text_release(&snapshot, &length, &error) == 0 && snapshot == NULL && length == 0);
	CHECK(text16_text_release(&snapshot, &length, &error) == 0);
	puts("PASS declaration-derived UTF-8 validation and independent owned text snapshots");
	return 0;
}
