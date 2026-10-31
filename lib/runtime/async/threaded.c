// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
/* Standalone legacy worker entry; common protocol/layout are task-core17.c. */
#define _POSIX_C_SOURCE 200809L
#define ASTRA_ASYNC_PTHREADS 1
#define ASTRA_ASYNC_LEGACY_WORKERS 1
#include <errno.h>
#include <pthread.h>
#include <time.h>
#include <string.h>
#include "task-core17.c"
#include "worker17.c"
#include "task-api17.c"
