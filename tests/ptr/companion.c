// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#include <stddef.h>
#include <stdint.h>

static int handle_a_storage;
static int handle_b_storage;
static int32_t predicate_count;

void *astra_test_handle_a(void) {
	return &handle_a_storage;
}

void *astra_test_handle_b(void) {
	return &handle_b_storage;
}

void *astra_test_null(void) {
	return NULL;
}

int32_t astra_test_is_handle_a(void *p) {
	return p == &handle_a_storage;
}

int32_t astra_test_is_handle_b(void *p) {
	return p == &handle_b_storage;
}

int32_t astra_test_is_null(void *p) {
	return p == NULL;
}

int32_t astra_test_guarded_handle_a(void *p) {
	predicate_count++;
	return p == &handle_a_storage;
}

int32_t astra_test_predicate_calls(void) {
	return predicate_count;
}

#ifdef ASTRA_TEST_PTR_EXPORT
extern void *astra_export_echo_ptr(void *p);

void *astra_test_pointer_roundtrip(void *p) {
	return astra_export_echo_ptr(p);
}

int32_t astra_test_check_pointer_roundtrip(void *p) {
	return astra_export_echo_ptr(p) == p;
}

#endif
