/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdio.h>
#include <stdlib.h>

struct resource {
	int id;
};
static void *slots[512];
static int ids[512];
static int count;
static int active;
static int errors;

void record_error(int stage, int tag) {
	if (stage == 1) {
		errors++;
		printf("E%d ", tag);
	} else if (stage == 2 && errors > 0) {
		errors--;
		printf("D%d ", tag);
	} else {
		abort();
	}
}
int record_errors(void) {
	return errors;
}

void *of_make(int id) {
	if (id == 0) {
		printf("N0 ");
		return NULL;
	}
	if (id < 0 || count == 512) {
		abort();
	}
	struct resource *value = malloc(sizeof *value);
	if (!value) {
		abort();
	}
	value->id = id;
	slots[count] = value;
	ids[count++] = id;
	active++;
	printf("A%d ", id);
	return value;
}
void of_release(void *value) {
	if (!value) {
		return;
	}
	for (int i = count - 1; i >= 0; i--) {
		if (slots[i] == value) {
			if (((struct resource *)value)->id != ids[i]) {
				abort();
			}
			printf("F%d ", ids[i]);
			slots[i] = NULL;
			active--;
			free(value);
			return;
		}
	}
	/* Check identity before dereferencing: the doubled-cleanup control aborts. */
	abort();
}
int of_live(void) {
	return active;
}
int of_mark(int code) {
	printf("M%d ", code);
	return code;
}
