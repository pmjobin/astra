// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#ifndef ASTRA_MONITORS_13_H
#define ASTRA_MONITORS_13_H
#include <stdint.h>

uint64_t astra_concurrency_thread_identity(void);
void astra_concurrency_thread_check(uint64_t expected);
void *astra_monitor_create(void);
void astra_monitor_internal(void *opaque);
void astra_monitor_enter(void *opaque);
void astra_monitor_leave(void *opaque);
void astra_monitor_destroy(void *opaque);
void astra_monitor_require_unlocked(void);
#endif
