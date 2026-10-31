// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Test-only allocator observation/injection for an exact, verified ET_EXEC.
// Generated sites.h maps public compiler emission and machine call return PCs.
// No native entry is called, no application value is supplied or retained.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "sites.h"

typedef struct {
	void *pointer;
	size_t bytes;
	int site;
	unsigned long id;
} Allocation;
static Allocation live[64];
static void *argument_snapshot;
static void *(*next_malloc)(size_t);
static void *(*next_calloc)(size_t, size_t);
static void (*next_free)(void *);
static unsigned long sequence, allocations, releases, allocated_bytes, live_bytes, peak_bytes, live_count, peak_count, errors;
static unsigned long last_numeric_release, argument_release, snapshot_release;
static int failure_site = -1;
static int configured;
static FILE *events;

static void resolve(void) {
	if (!next_malloc) {
		next_malloc = dlsym(RTLD_NEXT, "malloc");
	}
	if (!next_calloc) {
		next_calloc = dlsym(RTLD_NEXT, "calloc");
	}
	if (!next_free) {
		next_free = dlsym(RTLD_NEXT, "free");
	}
	if (!next_malloc || !next_calloc || !next_free) {
		_Exit(98);
	}
}

static void configure(void) {
	if (configured) {
		return;
	}
	configured = 1;
	const char *target = getenv("CAD_FAIL_SITE");
	if (target) {
		failure_site = atoi(target);
	}
	const char *path = getenv("CAD_EVENTS");
	if (path) {
		events = fopen(path, "w");
		if (!events) {
			_Exit(98);
		}
	}
}

void *malloc(size_t bytes) {
	resolve();
	void *result = next_malloc(bytes);
	uintptr_t caller = (uintptr_t)__builtin_return_address(0);
	if (caller >= ARGS_BEGIN && caller < ARGS_END) {
		argument_snapshot = result;
	}
	return result;
}

void *calloc(size_t count, size_t stride) {
	resolve();
	uintptr_t caller = (uintptr_t)__builtin_return_address(0);
	int site = 0;
	for (int i = 0; i < SITE_COUNT; ++i) {
		if (caller == sites[i].pc) {
			site = sites[i].id;
			if (stride != sites[i].stride) {
				++errors;
			}
			break;
		}
	}
	if (!site) {
		return next_calloc(count, stride);
	}
	configure();
	++sequence;
	if (site == failure_site) {
		if (events) {
			fprintf(events, "{\"event\":\"failure\",\"site\":%d,\"count\":%zu,\"stride\":%zu,\"sequence\":%lu}\n", site, count, stride, sequence);
			fflush(events);
		}
		return NULL;
	}
	void *result = next_calloc(count, stride);
	if (!result) {
		if (events) {
			fprintf(events, "{\"event\":\"allocator-null\",\"site\":%d,\"count\":%zu,\"stride\":%zu,\"sequence\":%lu}\n", site, count, stride, sequence);
			fflush(events);
		}
		return NULL;
	}
	++allocations;
	++live_count;
	allocated_bytes += count * stride;
	live_bytes += count * stride;
	if (live_bytes > peak_bytes) {
		peak_bytes = live_bytes;
	}
	if (live_count > peak_count) {
		peak_count = live_count;
	}
	for (int i = 0; i < 64; ++i) {
		if (!live[i].pointer) {
			live[i] = (Allocation){result, count * stride, site, allocations};
			if (events) {
				fprintf(events, "{\"event\":\"allocate\",\"site\":%d,\"count\":%zu,\"stride\":%zu,\"id\":%lu,\"sequence\":%lu}\n", site, count, stride, allocations, sequence);
			}
			return result;
		}
	}
	++errors;
	return result;
}

void free(void *pointer) {
	resolve();
	if (pointer) {
		for (int i = 0; i < 64; ++i) {
			if (live[i].pointer == pointer) {
				++releases;
				--live_count;
				live_bytes -= live[i].bytes;
				last_numeric_release = ++sequence;
				if (events) {
					fprintf(events, "{\"event\":\"free\",\"site\":%d,\"id\":%lu,\"sequence\":%lu}\n", live[i].site, live[i].id, sequence);
				}
				live[i].pointer = NULL;
				break;
			}
		}
		if (pointer == argument_snapshot) {
			snapshot_release = ++sequence;
			argument_snapshot = NULL;
		}
	}
	next_free(pointer);
}

void cad_arguments_free(void *arguments) {
	void (*next)(void *) = dlsym(RTLD_NEXT, "cad_arguments_free");
	if (!next) {
		_Exit(98);
	}
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
	fprintf(output, "{\"allocations\":%lu,\"releases\":%lu,\"allocated_bytes\":%lu,\"live_bytes\":%lu,\"peak_bytes\":%lu,\"live_count\":%lu,\"peak_count\":%lu,\"errors\":%lu,\"last_numeric_release\":%lu,\"argument_release\":%lu,\"ARGS_snapshot_release\":%lu}\n", allocations, releases, allocated_bytes, live_bytes, peak_bytes, live_count, peak_count, errors, last_numeric_release, argument_release, snapshot_release);
	if (fclose(output)) {
		_Exit(98);
	}
	if (events && fclose(events)) {
		_Exit(98);
	}
}
