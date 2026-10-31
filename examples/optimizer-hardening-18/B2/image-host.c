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

/* Byte/storage edges and observations. All image/component decisions are Astra. */
#define IMAGE2_PIXELS (257 * 129)
typedef struct {
	_Atomic int initialized, retired, labeled;
	int mask, score4, label;
} ImagePixel;
typedef struct {
	_Atomic int seen;
	int area, min_x, min_y, max_x, max_y;
	int64_t sum;
} ImageComponent;
typedef struct {
	_Atomic int stage, policy_seen, audit_seen;
	int mode, count;
	int64_t sum;
} ImageRow;
static ImagePixel pixels[IMAGE2_PIXELS];
static ImageComponent components[IMAGE2_PIXELS];
static ImageRow rows[129];
static unsigned char *input;
static char *output;
static int extent, width, height, threshold;
static _Atomic int dimensions_seen, invalid, jobs_seen[5], weak_dropped[4], weak_checked[4], active, peak_active;
static _Atomic uint64_t allocations[2], kernel_ns[2];
static _Thread_local int measuring, entered_lane;
static _Thread_local uint64_t entered;

void *__real_calloc(size_t, size_t);
void *__real_malloc(size_t);
void *__real_realloc(void *, size_t);
void *__wrap_calloc(size_t count, size_t size) {
	if (measuring) atomic_fetch_add(&allocations[measuring - 1], 1);
	return __real_calloc(count, size);
}
void *__wrap_malloc(size_t size) {
	if (measuring) atomic_fetch_add(&allocations[measuring - 1], 1);
	return __real_malloc(size);
}
void *__wrap_realloc(void *pointer, size_t size) {
	if (measuring) atomic_fetch_add(&allocations[measuring - 1], 1);
	return __real_realloc(pointer, size);
}
static uint64_t now(void) {
	struct timespec value;
	if (clock_gettime(CLOCK_MONOTONIC, &value)) abort();
	return (uint64_t)value.tv_sec * UINT64_C(1000000000) + (uint64_t)value.tv_nsec;
}
void image2_abort(void) {
	free(input);
	free(output);
	input = NULL;
	output = NULL;
}
static char *text_copy(const char *text, int count) {
	if (!text || count < 0 || memchr(text, 0, (size_t)count)) return NULL;
	char *copy = malloc((size_t)count + 1);
	if (copy) {
		memcpy(copy, text, (size_t)count);
		copy[count] = 0;
	}
	return copy;
}
int image2_prepare(const char *source, int source_count, const char *target, int target_count) {
	char *path = text_copy(source, source_count);
	output = text_copy(target, target_count);
	struct stat source_state, target_state;
	if (!path || !output || stat(path, &source_state) || !S_ISREG(source_state.st_mode) || source_state.st_size < 0 ||
	    source_state.st_size > 16 + IMAGE2_PIXELS * 3 || !strcmp(path, output) ||
	    (!stat(output, &target_state) && source_state.st_dev == target_state.st_dev && source_state.st_ino == target_state.st_ino)) {
		free(path);
		image2_abort();
		return 1;
	}
	extent = (int)source_state.st_size;
#ifndef IMAGE2_IO
	input = malloc(extent ? (size_t)extent : 1);
	FILE *file = fopen(path, "rb");
	if (!input || !file) {
		if (file) fclose(file);
		free(path);
		image2_abort();
		return 2;
	}
	int failed = fread(input, 1, (size_t)extent, file) != (size_t)extent || ferror(file);
	if (fclose(file)) failed = 1;
	if (failed) {
		free(path);
		image2_abort();
		return 3;
	}
#endif
	free(path);
	return 0;
}
int image2_size(void) {
	return extent;
}
int image2_byte(int index) {
	if (!input || index < 0 || index >= extent) abort();
	return input[index];
}
int image2_workers(void) {
	const char *text = getenv("ASTRA_IMAGE_WORKERS");
	if (!text || !*text) return 2;
	char *end = NULL;
	errno = 0;
	long count = strtol(text, &end, 10);
	if (errno || !end || *end || (count != 1 && count != 2 && count != 4)) abort();
	return (int)count;
}
void image2_scope_enter(int lane) {
	if (lane < 0 || lane > 4 || measuring || atomic_fetch_add(&jobs_seen[lane], 1)) abort();
	int busy = atomic_fetch_add(&active, 1) + 1;
	int peak = atomic_load(&peak_active);
	while (peak < busy && !atomic_compare_exchange_weak(&peak_active, &peak, busy)) {
	}
	entered = now();
	entered_lane = lane;
	measuring = lane == 4 ? 2 : 1;
}
void image2_scope_leave(int lane) {
	if (!measuring || lane != entered_lane) abort();
	atomic_fetch_add(&kernel_ns[measuring - 1], now() - entered);
	measuring = 0;
	if (atomic_fetch_sub(&active, 1) <= 0) abort();
}
void image2_dimensions(int w, int h, int t) {
	if (w < 0 || w > 257 || h < 0 || h > 129 || t < 0 || t > 255 || atomic_fetch_add(&dimensions_seen, 1)) {
		atomic_store(&invalid, 1);
		return;
	}
	width = w;
	height = h;
	threshold = t;
}
int image2_width(void) {
	if (atomic_load(&dimensions_seen) != 1) abort();
	return width;
}
int image2_height(void) {
	if (atomic_load(&dimensions_seen) != 1) abort();
	return height;
}
void image2_pixel(int index, int mask, int score4) {
	if (index < 0 || index >= IMAGE2_PIXELS || mask < 0 || mask > 1 || score4 < 0 || score4 > 1020) abort();
	if (atomic_fetch_add(&pixels[index].initialized, 1)) atomic_store(&invalid, 1);
	pixels[index].mask = mask;
	pixels[index].score4 = score4;
}
int image2_mask(int index) {
	if (index < 0 || index >= IMAGE2_PIXELS || atomic_load(&pixels[index].initialized) != 1) abort();
	return pixels[index].mask;
}
int image2_score4(int index) {
	if (index < 0 || index >= IMAGE2_PIXELS || atomic_load(&pixels[index].initialized) != 1) abort();
	return pixels[index].score4;
}
void image2_retire(int tag, int kind) {
	if (kind == 3) {
		if (tag < 0) {
			int64_t lane = -(int64_t)tag - 1;
			if (lane < 0 || lane >= 4 || atomic_fetch_add(&weak_dropped[lane], 1)) atomic_store(&invalid, 1);
		} else if (tag >= IMAGE2_PIXELS || atomic_fetch_add(&pixels[tag].retired, 1)) {
			atomic_store(&invalid, 1);
		}
		return;
	}
	if (tag < 0 || tag >= 129) {
		atomic_store(&invalid, 1);
		return;
	}
	int expected = kind == 2 ? 0 : kind == 1 ? 1
	                           : kind == 4   ? 2
	                                         : -1;
	if (expected < 0 || !atomic_compare_exchange_strong(&rows[tag].stage, &expected, expected + 1)) atomic_store(&invalid, 1);
}
void image2_weak_checked(int lane) {
	if (lane < 0 || lane >= 4 || atomic_fetch_add(&weak_checked[lane], 1)) atomic_store(&invalid, 1);
}
void image2_policy(int row, int mode) {
	if (row < 0 || row >= 129 || mode < 0 || mode > 1) abort();
	if (atomic_fetch_add(&rows[row].policy_seen, 1)) atomic_store(&invalid, 1);
	rows[row].mode = mode;
}
void image2_audit(int row, int count, int64_t sum) {
	if (row < 0 || row >= 129 || count < 0 || count > 257 || sum < 0) abort();
	if (atomic_fetch_add(&rows[row].audit_seen, 1)) atomic_store(&invalid, 1);
	rows[row].count = count;
	rows[row].sum = sum;
}
void image2_label(int index, int label) {
	if (index < 0 || index >= IMAGE2_PIXELS || label < 0 || label > IMAGE2_PIXELS) abort();
	if (atomic_fetch_add(&pixels[index].labeled, 1)) atomic_store(&invalid, 1);
	pixels[index].label = label;
}
void image2_component(int label, int area, int min_x, int min_y, int max_x, int max_y, int64_t sum) {
	if (label < 1 || label > IMAGE2_PIXELS || area < 1 || min_x < 0 || min_y < 0 || max_x < min_x || max_y < min_y || sum < 0) abort();
	ImageComponent *row = &components[label - 1];
	if (atomic_fetch_add(&row->seen, 1)) atomic_store(&invalid, 1);
	row->area = area;
	row->min_x = min_x;
	row->min_y = min_y;
	row->max_x = max_x;
	row->max_y = max_y;
	row->sum = sum;
}
int image2_context_done(AstraContext17 *context, int identity) {
	AstraContext17Snapshot state;
	if (astra_context17_snapshot(context, &state) || state.live || state.live_bytes || state.reserved_bytes ||
	    state.allocations != state.releases || state.borrowed || state.closed || state.threading != ASTRA_CONTEXT17_CONCURRENT) return 1;
	printf("image2 context=%d instance=%" PRIu64 " live=%" PRIu64 " reserved=%" PRIu64
	       " allocations=%" PRIu64 " releases=%" PRIu64 " peak_payload=%" PRIu64 "\n",
	       identity, state.instance, state.live, state.reserved_bytes, state.allocations, state.releases, state.peak_bytes);
	return 0;
}
static int word(FILE *file, uint32_t value) {
	unsigned char bytes[4];
	for (unsigned i = 0; i < 4; i++)
		bytes[i] = (unsigned char)(value >> (i * 8));
	return fwrite(bytes, 1, 4, file) == 4 ? 0 : 1;
}
static int wide(FILE *file, int64_t value) {
	uint64_t bits = (uint64_t)value;
	int error = word(file, (uint32_t)bits);
	error |= word(file, (uint32_t)(bits >> 32));
	return error;
}
int image2_finish(int count, int foreground) {
	if (count < 0 || count > IMAGE2_PIXELS || foreground < 0 || foreground > IMAGE2_PIXELS ||
	    atomic_load(&invalid) || atomic_load(&active) || atomic_load(&dimensions_seen) != 1) {
		image2_abort();
		return 10;
	}
	for (int lane = 0; lane < 5; lane++)
		if (atomic_load(&jobs_seen[lane]) != 1) {
			image2_abort();
			return 11;
		}
	for (int lane = 0; lane < 4; lane++) {
		if (atomic_load(&weak_checked[lane]) != 1 || atomic_load(&weak_dropped[lane]) != 1) {
			image2_abort();
			return 12;
		}
	}
	int extent_pixels = width * height, supplied = 0;
	for (int index = 0; index < IMAGE2_PIXELS; index++) {
		int used = index < extent_pixels;
		if (atomic_load(&pixels[index].initialized) != used || atomic_load(&pixels[index].retired) != used || atomic_load(&pixels[index].labeled) != used) {
			image2_abort();
			return 13;
		}
		int seen = atomic_load(&components[index].seen);
		if (seen < 0 || seen > 1 || (!used && seen)) {
			image2_abort();
			return 14;
		}
		supplied += seen;
	}
	if (supplied != count) {
		image2_abort();
		return 15;
	}
	for (int row = 0; row < 129; row++) {
		int used = row < height;
		if (atomic_load(&rows[row].stage) != used * 3 || atomic_load(&rows[row].policy_seen) != used || atomic_load(&rows[row].audit_seen) != used) {
			image2_abort();
			return 16;
		}
	}
	FILE *file = fopen(output, "wb");
	if (!file) {
		image2_abort();
		return 17;
	}
	int error = word(file, UINT32_C(0x434d5032));
	error |= word(file, (uint32_t)width);
	error |= word(file, (uint32_t)height);
	error |= word(file, (uint32_t)count);
	for (int index = 0; index < extent_pixels; index++)
		error |= word(file, (uint32_t)pixels[index].label);
	for (int index = 0; index < extent_pixels; index++) {
		ImageComponent *row = &components[index];
		if (!atomic_load(&row->seen)) continue;
		error |= word(file, (uint32_t)(index + 1));
		error |= word(file, (uint32_t)row->area);
		error |= word(file, (uint32_t)row->min_x);
		error |= word(file, (uint32_t)row->min_y);
		error |= word(file, (uint32_t)row->max_x);
		error |= word(file, (uint32_t)row->max_y);
		error |= wide(file, row->sum);
	}
	for (int row = 0; row < height; row++) {
		error |= word(file, (uint32_t)row);
		error |= word(file, (uint32_t)rows[row].count);
		error |= wide(file, rows[row].sum);
		printf("image2 policy=%d mode=%d\n", row, rows[row].mode);
	}
	if (fclose(file)) error = 1;
	printf("image2 width=%d height=%d threshold=%d components=%d foreground=%d classification_allocations=%" PRIu64
	       " merge_allocations=%" PRIu64 " classification_ns=%" PRIu64 " merge_ns=%" PRIu64 " peak_jobs=%d storage_bytes=%zu\n",
	       width, height, threshold, count, foreground, atomic_load(&allocations[0]), atomic_load(&allocations[1]), atomic_load(&kernel_ns[0]), atomic_load(&kernel_ns[1]),
	       atomic_load(&peak_active), sizeof(pixels) + sizeof(components) + sizeof(rows));
	image2_abort();
	return error ? 18 : 0;
}
