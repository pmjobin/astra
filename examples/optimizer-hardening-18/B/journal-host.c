/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <inttypes.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include "context-17.h"

/* File edges and observations only. Transaction decisions/state/undo are Astra. */
typedef struct {
	int code, failed, count;
	int64_t checksum;
	_Atomic int seen, stage, policy_seen;
	int policy;
} JournalRow;
typedef struct { int version, value, present; _Atomic int seen; } JournalState;
static unsigned char *input;
static char *output;
static int extent, row_capacity;
static JournalRow *rows;
static JournalState states[128];
static _Atomic int invalid, weak_dropped[4], weak_checked[4], jobs_seen[4];
static _Atomic int active, peak_active;
static _Atomic uint64_t allocations, kernel_ns;
static _Thread_local int measuring;
static _Thread_local uint64_t entered;

void *__real_calloc(size_t, size_t);
void *__real_malloc(size_t);
void *__real_realloc(void *, size_t);
void *__wrap_calloc(size_t count, size_t size) {
	if (measuring) atomic_fetch_add(&allocations, 1);
	return __real_calloc(count, size);
}
void *__wrap_malloc(size_t size) {
	if (measuring) atomic_fetch_add(&allocations, 1);
	return __real_malloc(size);
}
void *__wrap_realloc(void *pointer, size_t size) {
	if (measuring) atomic_fetch_add(&allocations, 1);
	return __real_realloc(pointer, size);
}
static uint64_t now(void) {
	struct timespec value;
	if (clock_gettime(CLOCK_MONOTONIC, &value)) abort();
	return (uint64_t)value.tv_sec * UINT64_C(1000000000) + (uint64_t)value.tv_nsec;
}
void journal18_abort(void) {
	free(input); free(output); free(rows);
	input = NULL; output = NULL; rows = NULL;
}
static char *text_copy(const char *text, int count) {
	if (!text || count < 0 || memchr(text, 0, (size_t)count)) return NULL;
	char *copy = malloc((size_t)count + 1);
	if (copy) { memcpy(copy, text, (size_t)count); copy[count] = 0; }
	return copy;
}
int journal18_prepare(const char *source, int source_count, const char *target, int target_count) {
	char *path = text_copy(source, source_count);
	output = text_copy(target, target_count);
	struct stat source_state, target_state;
	if (!path || !output || stat(path, &source_state) || !S_ISREG(source_state.st_mode) || source_state.st_size < 0 ||
		source_state.st_size > 8193 * 16 || source_state.st_size % 16 ||
		!strcmp(path, output) || (!stat(output, &target_state) &&
		 source_state.st_dev == target_state.st_dev && source_state.st_ino == target_state.st_ino)) {
		free(path); journal18_abort(); return 1;
	}
	extent = (int)source_state.st_size;
	row_capacity = extent / 16 + 1;
	rows = calloc((size_t)row_capacity, sizeof(*rows));
#ifndef JOURNAL18_IO
	input = malloc(extent ? (size_t)extent : 1);
	FILE *file = fopen(path, "rb");
	if (!input || !rows || !file) {
		if (file) fclose(file);
		free(path); journal18_abort(); return 2;
	}
	int failed = fread(input, 1, (size_t)extent, file) != (size_t)extent || ferror(file);
	if (fclose(file)) failed = 1;
	if (failed) { free(path); journal18_abort(); return 3; }
#else
	if (!rows) { free(path); journal18_abort(); return 2; }
#endif
	free(path);
	return 0;
}
int journal18_size(void) { return extent; }
int journal18_input_byte(int index) {
	if (!input || index < 0 || index >= extent) abort();
	return input[index];
}
int journal18_workers(void) {
	const char *text = getenv("ASTRA_JOURNAL_WORKERS");
	if (!text || !*text) return 2;
	char *end = NULL;
	errno = 0;
	long count = strtol(text, &end, 10);
	if (errno || !end || *end || (count != 1 && count != 2 && count != 4)) abort();
	return (int)count;
}
void journal18_scope_enter(int lane) {
	if (lane < 0 || lane >= 4 || measuring || atomic_fetch_add(&jobs_seen[lane], 1)) abort();
	int busy = atomic_fetch_add(&active, 1) + 1;
	int peak = atomic_load(&peak_active);
	while (peak < busy && !atomic_compare_exchange_weak(&peak_active, &peak, busy)) {}
	entered = now(); measuring = 1;
}
void journal18_scope_leave(int lane) {
	if (lane < 0 || lane >= 4 || !measuring) abort();
	measuring = 0;
	atomic_fetch_add(&kernel_ns, now() - entered);
	if (atomic_fetch_sub(&active, 1) <= 0) abort();
}
void journal18_retire(int transaction, int kind) {
	if (transaction < 0) {
		int64_t lane = -(int64_t)transaction - 1;
		if (lane < 0 || lane >= 4 || kind != 3 || atomic_fetch_add(&weak_dropped[lane], 1)) atomic_store(&invalid, 1);
		return;
	}
	if (transaction >= row_capacity) { atomic_store(&invalid, 1); return; }
	int expected = kind == 2 ? 0 : kind == 1 ? 1 : kind == 3 ? 2 : kind == 4 ? 3 : -1;
	if (expected < 0 || !atomic_compare_exchange_strong(&rows[transaction].stage, &expected, expected + 1)) atomic_store(&invalid, 1);
}
void journal18_policy_call(int transaction, int value) {
	if (transaction < 0 || transaction >= row_capacity || value < 0 || value > 3) { atomic_store(&invalid, 1); return; }
	if (atomic_fetch_add(&rows[transaction].policy_seen, 1)) atomic_store(&invalid, 1);
	rows[transaction].policy = value;
}
void journal18_weak_checked(int lane) {
	if (lane < 0 || lane >= 4 || atomic_fetch_add(&weak_checked[lane], 1)) atomic_store(&invalid, 1);
}
void journal18_result(int transaction, int code, int failed, int count, int64_t checksum) {
	if (transaction < 0 || transaction >= row_capacity || atomic_fetch_add(&rows[transaction].seen, 1)) { atomic_store(&invalid, 1); return; }
	rows[transaction].code = code; rows[transaction].failed = failed;
	rows[transaction].count = count; rows[transaction].checksum = checksum;
}
void journal18_state(int lane, int key, int version, int value, int present) {
	if (lane < 0 || lane >= 4 || key < 0 || key >= 32) { atomic_store(&invalid, 1); return; }
	JournalState *state = &states[lane * 32 + key];
	if (atomic_fetch_add(&state->seen, 1)) atomic_store(&invalid, 1);
	state->version = version; state->value = value; state->present = present;
}
int journal18_context_done(AstraContext17 *context, int identity) {
	AstraContext17Snapshot state;
	if (astra_context17_snapshot(context, &state) || state.live || state.live_bytes || state.reserved_bytes ||
		state.allocations != state.releases || state.borrowed || state.closed || state.threading != ASTRA_CONTEXT17_CONCURRENT) return 1;
	printf("journal18 context=%d instance=%" PRIu64 " live=%" PRIu64 " reserved=%" PRIu64
		" allocations=%" PRIu64 " releases=%" PRIu64 " peak_payload=%" PRIu64 "\n",
		identity, state.instance, state.live, state.reserved_bytes, state.allocations, state.releases, state.peak_bytes);
	return 0;
}
static int word(FILE *file, uint32_t value) {
	unsigned char bytes[4];
	for (unsigned i = 0; i < 4; i++) bytes[i] = (unsigned char)(value >> (i * 8));
	return fwrite(bytes, 1, 4, file) == 4 ? 0 : 1;
}
int journal18_finish(int transactions) {
	if (transactions < 0 || transactions >= row_capacity || atomic_load(&invalid) || atomic_load(&active)) { journal18_abort(); return 10; }
	for (int lane = 0; lane < 4; lane++) {
		if (atomic_load(&jobs_seen[lane]) != 1 || atomic_load(&weak_checked[lane]) != 1 || atomic_load(&weak_dropped[lane]) != 1) { journal18_abort(); return 11; }
	}
	for (int i = 0; i < row_capacity; i++) {
		int used = i < transactions;
		if (atomic_load(&rows[i].seen) != used || atomic_load(&rows[i].stage) != used * 4 || atomic_load(&rows[i].policy_seen) != used) { journal18_abort(); return 12; }
	}
	for (int i = 0; i < 128; i++) if (atomic_load(&states[i].seen) != 1) { journal18_abort(); return 13; }
	FILE *file = fopen(output, "wb");
	if (!file) { journal18_abort(); return 14; }
	int error = word(file, UINT32_C(0x4a4f5531)) | word(file, (uint32_t)transactions);
	for (int i = 0; i < transactions; i++) {
		JournalRow *row = &rows[i];
		error |= word(file, (uint32_t)i) | word(file, (uint32_t)row->code) | word(file, (uint32_t)row->failed) | word(file, (uint32_t)row->count);
		uint64_t checksum = (uint64_t)row->checksum;
		error |= word(file, (uint32_t)checksum) | word(file, (uint32_t)(checksum >> 32));
		printf("journal18 policy=%d value=%d\n", i, row->policy);
	}
	for (int i = 0; i < 128; i++) {
		JournalState *state = &states[i];
		error |= word(file, (uint32_t)(i / 32)) | word(file, (uint32_t)(i % 32)) | word(file, (uint32_t)state->version) | word(file, (uint32_t)state->value) | word(file, (uint32_t)state->present);
	}
	if (fclose(file)) error = 1;
	printf("journal18 transactions=%d allocations=%" PRIu64 " kernel_ns=%" PRIu64 " peak_jobs=%d\n",
		transactions, atomic_load(&allocations), atomic_load(&kernel_ns), atomic_load(&peak_active));
	journal18_abort();
	return error ? 15 : 0;
}
