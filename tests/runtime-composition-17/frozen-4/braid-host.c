/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _POSIX_C_SOURCE 200809L
#include "braid-provider.h"
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "signal stop requires a lock-free atomic");
static _Atomic int stopped;
static struct sigaction previous_int, previous_term;
static struct timespec began;
static int queue_capacity, cache_capacity, workers, quota, extent, verbose;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned tickets, retired_tickets, entries, retired_entries, analyses, active, peak, reads, responses, refusals, network_overlap, io_overlap;
static void stop(int signal) { (void)signal; atomic_store_explicit(&stopped, 1, memory_order_relaxed); }
static int option(const char *name, int fallback, int low, int high)
{
	const char *value = getenv(name); if (!value) { return fallback; }
	errno = 0; char *end = NULL; long parsed = strtol(value, &end, 10);
	return errno || end == value || *end || parsed < low || parsed > high ? -1 : (int)parsed;
}
int braid_prepare(const unsigned char *path, int length)
{
	if (!path || length <= 0 || length > 4095) { return 1; }
	char local[4096];
	for (int i = 0; i < length; ++i) { if (!path[i]) { return 1; } local[i] = (char)path[i]; }
	local[length] = 0; struct stat file;
	queue_capacity = option("ASTRA_BRAID_QUEUE", 4, 1, 9);
	cache_capacity = option("ASTRA_BRAID_CACHE", 7, 1, 9);
	workers = option("ASTRA_BRAID_WORKERS", 4, 2, 6);
	quota = option("ASTRA_BRAID_QUOTA", 131071, 65537, 1048573);
	if (queue_capacity < 0 || cache_capacity < 0 || workers < 0 || quota < 0 ||
		stat(local, &file) || !S_ISREG(file.st_mode) || file.st_size <= 0 || file.st_size >= 16777216) { return 1; }
	extent = (int)file.st_size; verbose = getenv("ASTRA_BRAID_EVENTS") != NULL;
	struct sigaction action = {.sa_handler = stop};
	if (sigemptyset(&action.sa_mask) || sigaction(SIGINT, &action, &previous_int) ||
		sigaction(SIGTERM, &action, &previous_term) || clock_gettime(CLOCK_MONOTONIC, &began)) { abort(); }
	return 0;
}
int braid_stop_requested(void) { return atomic_load_explicit(&stopped, memory_order_relaxed); }
int braid_queue_capacity(void) { return queue_capacity; }
int braid_cache_capacity(void) { return cache_capacity; }
int braid_worker_count(void) { return workers; }
int braid_quota(void) { return quota; }
int braid_file_extent(void) { return extent; }
void braid_ready(int tcp, int udp)
{
	printf("{\"tcp\":%d,\"udp\":%d,\"pid\":%ld}\n", tcp, udp, (long)getpid()); assert(fflush(stdout) == 0);
}
void braid_event(int kind, int identity, int value)
{
	assert(pthread_mutex_lock(&lock) == 0);
	switch (kind) {
	case 0: ++tickets; break;
	case 1: ++retired_tickets; break;
	case 2: ++analyses; ++active; if (active > peak) { peak = active; } break;
	case 3: assert(active > 0); --active; break;
	case 4: ++reads; if (active) { ++io_overlap; } break;
	case 6: ++entries; break;
	case 7: ++retired_entries; break;
	case 8: assert(identity > 0 && identity <= value && value == queue_capacity); break;
	case 9: ++refusals; break;
	case 12: if (active) { ++network_overlap; } break;
	case 13: ++responses; if (active) { ++network_overlap; } break;
	default: break;
	}
	if (verbose) { printf("{\"event\":%d,\"identity\":%d,\"value\":%d}\n", kind, identity, value); assert(fflush(stdout) == 0); }
	assert(pthread_mutex_unlock(&lock) == 0);
}
void braid_error(const unsigned char *message, int length)
{
	assert(message && length >= 0); if (length > 1024) { length = 1024; }
	fputs("braid: ", stderr); fwrite(message, 1, (size_t)length, stderr); fputc('\n', stderr);
}
int braid_finish(int result)
{
	struct timespec end;
	assert(clock_gettime(CLOCK_MONOTONIC, &end) == 0 && sigaction(SIGINT, &previous_int, NULL) == 0 && sigaction(SIGTERM, &previous_term, NULL) == 0);
	assert(pthread_mutex_lock(&lock) == 0);
	assert(active == 0 && tickets == retired_tickets && entries == retired_entries);
	long long milliseconds = (long long)(end.tv_sec - began.tv_sec) * 1000 + (end.tv_nsec - began.tv_nsec) / 1000000;
	printf("{\"result\":%d,\"milliseconds\":%lld,\"tickets\":%u,\"retired_tickets\":%u,\"entries\":%u,\"retired_entries\":%u,\"analyses\":%u,\"cpu_peak\":%u,\"reads\":%u,\"responses\":%u,\"refusals\":%u,\"network_overlap\":%u,\"io_overlap\":%u}\n", result, milliseconds, tickets, retired_tickets, entries, retired_entries, analyses, peak, reads, responses, refusals, network_overlap, io_overlap);
	assert(pthread_mutex_unlock(&lock) == 0);
	if (braid_provider_finish() != 0) { return 1; }
	return result;
}
