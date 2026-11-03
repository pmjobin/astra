// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Optional L/P observer. Counts only; never supplies numerical reference values.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct {
	void *pointer;
	uint64_t bytes;
} Allocation;

static Allocation live[64];
static uint64_t allocations, releases, allocated_bytes, live_bytes, peak_bytes, live_count, peak_count, gets, sets, errors;
static uint64_t arguments_created, argument_copies, argument_bytes, arguments_released, sequence, last_numeric_release, argument_release;

static void *symbol(const char *name) {
	void *address = dlsym(RTLD_NEXT, name);
	if (!address) {
		fputs("CAD observer could not resolve symbol\n", stderr);
		_Exit(98);
	}
	return address;
}

void *cad_buffer(int32_t count) {
	static void *(*next)(int32_t);
	if (!next) {
		next = symbol("cad_buffer");
	}
	void *result = next(count);
	uint64_t bytes = 8 + (uint64_t)count * sizeof(double);
	++allocations;
	allocated_bytes += bytes;
	++live_count;
	live_bytes += bytes;
	if (live_count > peak_count) {
		peak_count = live_count;
	}
	if (live_bytes > peak_bytes) {
		peak_bytes = live_bytes;
	}
	for (int i = 0; i < 64; ++i) {
		if (!live[i].pointer) {
			live[i].pointer = result;
			live[i].bytes = bytes;
			return result;
		}
	}
	++errors;
	return result;
}

void cad_free(void *pointer) {
	static void (*next)(void *);
	if (!next) {
		next = symbol("cad_free");
	}
	int found = 0;
	for (int i = 0; i < 64; ++i) {
		if (pointer && live[i].pointer == pointer) {
			live_bytes -= live[i].bytes;
			--live_count;
			live[i].pointer = NULL;
			found = 1;
			break;
		}
	}
	if (!found) {
		++errors;
	}
	++releases;
	last_numeric_release = ++sequence;
	next(pointer);
}

double cad_get(void *pointer, int32_t index) {
	static double (*next)(void *, int32_t);
	if (!next) {
		next = symbol("cad_get");
	}
	++gets;
	return next(pointer, index);
}

void cad_set(void *pointer, int32_t index, double value) {
	static void (*next)(void *, int32_t, double);
	if (!next) {
		next = symbol("cad_set");
	}
	++sets;
	next(pointer, index, value);
}

void *cad_arguments_new(int32_t count) {
	static void *(*next)(int32_t);
	if (!next) {
		next = symbol("cad_arguments_new");
	}
	void *result = next(count);
	if (result) {
		++arguments_created;
		argument_bytes += 8 + ((uint64_t)count + 1) * sizeof(char *);
	}
	return result;
}

int32_t cad_arguments_copy(void *arguments, int32_t index, const unsigned char *text, int32_t length) {
	static int32_t (*next)(void *, int32_t, const unsigned char *, int32_t);
	if (!next) {
		next = symbol("cad_arguments_copy");
	}
	int32_t result = next(arguments, index, text, length);
	if (!result) {
		++argument_copies;
		argument_bytes += (uint64_t)length + 1;
	}
	return result;
}

void cad_arguments_free(void *arguments) {
	static void (*next)(void *);
	if (!next) {
		next = symbol("cad_arguments_free");
	}
	++arguments_released;
	argument_release = ++sequence;
	next(arguments);
}

__attribute__((destructor)) static void report(void) {
	const char *path = getenv("CAD_OBSERVER_OUTPUT");
	if (!path) {
		return;
	}
	FILE *output = fopen(path, "w");
	if (!output) {
		_Exit(98);
	}
	fprintf(output, "{\"numeric_allocations\":%" PRIu64 ",\"numeric_releases\":%" PRIu64 ",\"numeric_allocated_bytes\":%" PRIu64 ",\"numeric_live_bytes\":%" PRIu64 ",\"numeric_peak_bytes\":%" PRIu64 ",\"numeric_live_count\":%" PRIu64 ",\"numeric_peak_count\":%" PRIu64 ",\"cad_get_calls\":%" PRIu64 ",\"cad_set_calls\":%" PRIu64 ",\"observer_errors\":%" PRIu64 ",\"argument_tables\":%" PRIu64 ",\"argument_copies\":%" PRIu64 ",\"argument_bytes\":%" PRIu64 ",\"argument_table_releases\":%" PRIu64 ",\"last_numeric_release_sequence\":%" PRIu64 ",\"argument_release_sequence\":%" PRIu64 "}\n", allocations, releases, allocated_bytes, live_bytes, peak_bytes, live_count, peak_count, gets, sets, errors, arguments_created, argument_copies, argument_bytes, arguments_released, last_numeric_release, argument_release);
	if (fclose(output)) {
		_Exit(98);
	}
}
