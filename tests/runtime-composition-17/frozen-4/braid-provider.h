/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_BRAID_PROVIDER_H
#define ASTRA_BRAID_PROVIDER_H
#include "../../../lib/astra/runtime/context-17.h"
AstraContext17 *braid_custom_allocator(int64_t capacity, int32_t slots, int32_t identity);
int braid_provider_disposed(int32_t identity);
int braid_provider_finish(void);
#endif
