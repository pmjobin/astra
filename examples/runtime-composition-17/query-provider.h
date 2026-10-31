/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_QUERY_PROVIDER_H
#define ASTRA_QUERY_PROVIDER_H
#include "../../lib/runtime/runtime/context-17.h"
AstraContext17 *query_custom_allocator(int64_t capacity, int32_t slots, int32_t identity);
int query_provider_disposed(int32_t identity);
int query_provider_finish(void);
#endif
