// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#ifndef ASTRA_FOREIGN_14_H
#define ASTRA_FOREIGN_14_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Compiler-private thread identity service. Never an object/refcount authority.
// Tokens are never recycled while the process continues; exhaustion aborts.
uint64_t astra_foreign14_thread_identity(void);
#ifdef __cplusplus
}
#endif
#endif
