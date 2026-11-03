/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Actual independent C resources and observation only; algorithms are Astra. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

struct lease {
	int32_t id;
	int domain;
};
static struct lease *active[256];

static int find_live(void *pointer) {
	if (pointer != NULL) {
		for (int slot = 0; slot < 256; slot++) {
			if (active[slot] == pointer) {
				return slot;
			}
		}
	}
	abort();
}

static void *acquire(int32_t id, int domain) {
	assert(id > 0 && id < 256);
	int slot = 0;
	while (slot < 256 && active[slot] != NULL) {
		slot++;
	}
	assert(slot < 256);
	struct lease *value = malloc(sizeof *value);
	assert(value != NULL);
	*value = (struct lease){id, domain};
	active[slot] = value;
	printf("+%d\n", id);
	fflush(stdout);
	return value;
}

void *surge_open(int32_t id) {
	return acquire(id, 0);
}

void *surge_open_other(int32_t id) {
	return acquire(id, 1);
}

static void retire(void *pointer, int domain) {
	int slot = find_live(pointer);
	struct lease *value = active[slot];
	assert(value->domain == domain);
	printf("-%d\n", value->id);
	fflush(stdout);
	active[slot] = NULL;
	free(value);
}

void surge_close(void *pointer) {
	retire(pointer, 0);
}

void surge_close_other(void *pointer) {
	retire(pointer, 1);
}

int32_t surge_id(void *pointer) {
	struct lease *value = active[find_live(pointer)];
	return value->id;
}

int32_t surge_other_id(void *pointer) {
	return surge_id(pointer);
}

int32_t surge_live(void) {
	int32_t result = 0;
	for (int id = 0; id < 256; id++) {
		result += active[id] != NULL;
	}
	return result;
}

int32_t surge_event(int32_t value) {
	printf("E%d\n", value);
	fflush(stdout);
	return value;
}

int32_t surge_number(int32_t value) {
	printf("N%d\n", value);
	fflush(stdout);
	return value;
}
