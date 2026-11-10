/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

struct Slots {
	void **data;
	int count;
	int capacity;
};

struct Item {
	int code;
};

_Static_assert(sizeof(void *) == 8, "LP64 pointer");
_Static_assert(sizeof(struct Slots) == 16, "slot descriptor size");
_Static_assert(_Alignof(struct Slots) == 8, "slot descriptor alignment");
_Static_assert(offsetof(struct Slots, data) == 0, "slot data");
_Static_assert(offsetof(struct Slots, count) == 8, "slot count");
_Static_assert(offsetof(struct Slots, capacity) == 12, "slot capacity");

extern bool slot_reserve(struct Slots *, int);
extern void slot_append(struct Slots *, void *);
extern void *slot_take(struct Slots *, int);
extern void slot_replace(struct Slots *, int, void *);
extern void slot_drop(struct Slots *);

static int trace[8];
static int events;

static struct Item *item(int code) {
	struct Item *value = malloc(sizeof *value);
	assert(value);
	value->code = code;
	return value;
}

void observe_drop(void *pointer) {
	struct Item *value = pointer;
	assert(value && events < 8);
	trace[events++] = value->code;
	printf("%d\n", value->code);
	free(value);
}

int main(int argc, char **argv) {
	struct Slots values = {0};
	int fault = argc > 1 ? atoi(argv[1]) : 0;
	if (fault == 1) {
		slot_append(&values, item(1));
		return 90;
	}
	if (fault == 2) {
		values.count = -1;
		slot_drop(&values);
		return 91;
	}
	if (fault == 3) {
		values.capacity = 1;
		slot_drop(&values);
		return 92;
	}
	assert(!slot_reserve(&values, -1));
	assert(!values.data && values.count == 0 && values.capacity == 0);
	assert(slot_reserve(&values, 2));
	assert(values.data && values.count == 0 && values.capacity == 2);
	slot_append(&values, item(20));
	slot_append(&values, item(22));
	if (fault == 4) {
		(void)slot_take(&values, -1);
		return 93;
	}
	if (fault == 5) {
		slot_replace(&values, 0, values.data[0]);
		return 94;
	}
	if (fault == 6) {
		slot_replace(&values, 0, NULL);
		return 95;
	}
	assert(slot_reserve(&values, 5));
	assert(values.count == 2 && values.capacity == 5 && events == 0);
	struct Item *taken = slot_take(&values, 0);
	assert(taken->code == 20 && values.count == 1);
	assert(((struct Item *)values.data[0])->code == 22 && values.data[1] == NULL);
	slot_replace(&values, 0, item(24));
	assert(events == 1 && trace[0] == 22);
	slot_append(&values, taken);
	taken = NULL;
	slot_drop(&values);
	assert(!values.data && values.count == 0 && values.capacity == 0);
	assert(events == 3 && trace[0] == 22 && trace[1] == 20 && trace[2] == 24);
	slot_drop(&values);
	assert(events == 3);
	return 42;
}
