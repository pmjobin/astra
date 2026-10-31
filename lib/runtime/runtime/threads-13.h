// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#ifndef ASTRA_THREADS_13_H
#define ASTRA_THREADS_13_H
#include <stdint.h>

// Compiler-private carrier entry. No native environment escapes this protocol.
typedef int32_t (*astra_thread_callback)(void *, int32_t);
void *astra_thread_register(astra_thread_callback callback, void *context, int32_t argument);
int32_t astra_thread_join(void *token);
int32_t astra_thread_cancel(void *token);
int32_t astra_thread_retire(void *token);

// A cooperative cancellation observation for the currently executing worker.
int32_t astra_worker_cancelled(void);
#endif
