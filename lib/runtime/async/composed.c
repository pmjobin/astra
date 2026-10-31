// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
/* One core for cooperative, pthread and the separately linked Linux provider. */
#define _POSIX_C_SOURCE 200809L
#define ASTRA_ASYNC_PTHREADS 1
#include <errno.h>
#include <pthread.h>
#include <time.h>
#include <string.h>
#include "task-core17.c"
#include "worker17.c"
#include "task-api17.c"
