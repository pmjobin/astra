/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_CONTEXT17_TEST_PROVIDER_H
#define ASTRA_CONTEXT17_TEST_PROVIDER_H
#include "../../lib/runtime/runtime/context-17.h"
#include <stdatomic.h>
typedef struct TestContextProvider {
	unsigned char *backing;
	uint64_t capacity, used, live, attempts, releases, fail_at;
	_Atomic int *disposed;
	AstraContext17 *context;
	int test_reentry;
} TestContextProvider;
TestContextProvider *test_context_provider(uint64_t, _Atomic int *);
extern const AstraContext17Provider test_context_contract;
AstraContext17 *m17_custom_allocator(int64_t, int32_t);
int m17_custom_provider_retired(void);
#endif
