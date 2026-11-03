// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Test-only observation of actual emitted Astra owners and backing stores.
// This table supplies no production ownership or collection behavior.
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct Slots {
	void **base;
	int32_t length, capacity;
};

struct Message {
	const unsigned char *bytes;
	int32_t length;
};

struct Diagnostic {
	int32_t tag;
	struct Message *message;
};

_Static_assert(sizeof(struct Slots) == 16 && offsetof(struct Slots, length) == 8 && offsetof(struct Slots, capacity) == 12, "qualified owner-slot layout");
_Static_assert(sizeof(struct Diagnostic) == 16 && offsetof(struct Diagnostic, message) == 8, "exact diagnostic layout");
_Static_assert(sizeof(struct Message) == 16 && offsetof(struct Message, length) == 8, "exact snapshot layout");

enum Role { OTHER,
	        BAG,
	        BACKING,
	        DIAGNOSTIC,
	        MESSAGE,
	        PAYLOAD };

struct Allocation {
	void *pointer;
	size_t count, stride;
	enum Role role;
	bool live, retiring;
};

struct Element {
	struct Diagnostic *pointer;
	struct Message *message;
	const unsigned char *bytes;
	int32_t length, tag;
	unsigned char snapshot[64];
	int bag, state;
	bool freed;
};

struct Bag {
	struct Slots *pointer;
	void **backing;
	struct Diagnostic *elements[16];
	int length, capacity;
	bool dropping, dropped;
};
static struct Allocation allocations[512];
static struct Element elements[32];
static struct Bag bags[16];
static int allocation_count, element_count, bag_count, growth_count, borrow_count;
void *__real_calloc(size_t, size_t);
void *__real_malloc(size_t);
void __real_free(void *);

static void flush(void) {
	fflush(stdout);
}

static int allocation(void *pointer) {
	if (!pointer) return 0;
	for (int i = allocation_count; i > 0; --i)
		if (allocations[i].pointer == pointer && allocations[i].live) return i;
	assert(!"pointer is not an actual live allocation");
	return 0;
}

static int element(struct Diagnostic *pointer) {
	for (int i = element_count; i > 0; --i)
		if (elements[i].pointer == pointer && !elements[i].freed) return i;
	assert(!"unknown diagnostic identity");
	return 0;
}

static int bag(struct Slots *pointer) {
	for (int i = bag_count; i > 0; --i)
		if (bags[i].pointer == pointer && !bags[i].dropped) return i;
	assert(!"unknown collection identity");
	return 0;
}

static void role(void *pointer, enum Role role_value) {
	if (!pointer) return;
	int id = allocation(pointer);
	assert(allocations[id].role == OTHER);
	allocations[id].role = role_value;
}

static void stable(int id) {
	struct Element *entry = &elements[id];
	assert(!entry->freed && allocation(entry->pointer) && allocation(entry->message));
	assert(entry->pointer->tag == entry->tag && entry->pointer->message == entry->message);
	assert(entry->message->bytes == entry->bytes && entry->message->length == entry->length);
	if (entry->length) {
		assert(allocation((void *)entry->bytes));
		assert(!memcmp(entry->bytes, entry->snapshot, (size_t)entry->length));
	}
}

static void *record(void *pointer, size_t count, size_t stride, char kind) {
	assert(pointer && allocation_count + 1 < 512);
	int id = ++allocation_count;
	allocations[id] = (struct Allocation){pointer, count, stride, OTHER, true, false};
	printf("A%d %c %zu:%zu\n", id, kind, count, stride);
	flush();
	return pointer;
}

void *__wrap_malloc(size_t bytes) {
	return record(__real_malloc(bytes), 1, bytes, 'M');
}

void *__wrap_calloc(size_t count, size_t stride) {
	if (count == 3 && stride == sizeof(void *) && getenv("SLOTS_FAIL_GROW")) {
		puts("OOM growth");
		flush();
		return NULL;
	}
	return record(__real_calloc(count, stride), count, stride, 'C');
}

void __wrap_free(void *pointer) {
	if (!pointer) {
		__real_free(pointer);
		return;
	}
	int id = allocation(pointer);
	enum Role purpose = allocations[id].role;
	if (purpose == BACKING) {
		assert(allocations[id].retiring);
		for (int b = 1; b <= bag_count; ++b)
			if (bags[b].backing == pointer && bags[b].dropping) assert(bags[b].length == 0);
	} else if (purpose == DIAGNOSTIC) {
		int e = element(pointer);
		assert(elements[e].state == 3);
		for (int i = 1; i <= allocation_count; ++i)
			if (allocations[i].pointer == elements[e].message) assert(!allocations[i].live);
		elements[e].freed = true;
	} else if (purpose == MESSAGE || purpose == PAYLOAD) {
		bool matched = false;
		for (int e = 1; e <= element_count; ++e) {
			struct Element *entry = &elements[e];
			if (entry->freed || (purpose == MESSAGE ? (void *)entry->message != pointer : (void *)entry->bytes != pointer)) continue;
			assert(entry->state == 3);
			matched = true;
			if (purpose == MESSAGE && entry->length)
				for (int i = 1; i <= allocation_count; ++i)
					if (allocations[i].pointer == entry->bytes) assert(!allocations[i].live);
		}
		assert(matched);
	} else if (purpose == BAG) {
		bool matched = false;
		for (int b = 1; b <= bag_count; ++b)
			if (bags[b].pointer == pointer && bags[b].dropped) matched = true;
		assert(matched);
	}
	allocations[id].live = false;
	printf("F%d\n", id);
	flush();
	__real_free(pointer);
}

void slot_obs_born(struct Diagnostic *pointer, int32_t tag, struct Message *message) {
	assert(element_count + 1 < 32 && pointer->tag == tag && pointer->message == message);
	assert(message->length >= 0 && message->length < 64);
	int id = ++element_count;
	elements[id] = (struct Element){.pointer = pointer, .message = message, .bytes = message->bytes, .length = message->length, .tag = tag, .state = 1};
	if (message->length) memcpy(elements[id].snapshot, message->bytes, (size_t)message->length);
	role(pointer, DIAGNOSTIC);
	role(message, MESSAGE);
	role((void *)message->bytes, PAYLOAD);
	stable(id);
	printf("I%d tag=%d object=%d message=%d bytes=%d\n", id, tag, allocation(pointer), allocation(message), allocation((void *)message->bytes));
	flush();
}

void slot_obs_init(struct Slots *pointer) {
	assert(bag_count + 1 < 16 && !pointer->base && !pointer->length && !pointer->capacity);
	int id = ++bag_count;
	bags[id] = (struct Bag){.pointer = pointer};
	role(pointer, BAG);
	printf("B%d object=%d\n", id, allocation(pointer));
	flush();
}

void slot_obs_commit(struct Slots *pointer, void **old, void **replacement, int32_t length, int32_t capacity) {
	int b = bag(pointer);
	struct Bag *state = &bags[b];
	assert(old == state->backing && replacement && replacement != old && length == state->length && capacity > state->capacity);
	assert(pointer->base == replacement && pointer->length == length && pointer->capacity == capacity);
	int id = allocation(replacement);
	assert(allocations[id].count == (size_t)capacity && allocations[id].stride == sizeof(void *));
	role(replacement, BACKING);
	for (int i = 0; i < length; ++i) {
		assert(replacement[i] == state->elements[i] && !old[i]);
		stable(element(replacement[i]));
	}
	for (int i = length; i < capacity; ++i)
		assert(!replacement[i]);
	int prior = allocation(old);
	if (prior) allocations[prior].retiring = true;
	if (state->capacity) ++growth_count;
	printf("G%d %d->%d len=%d old=%d new=%d\n", b, state->capacity, capacity, length, prior, id);
	flush();
	state->backing = replacement;
	state->capacity = capacity;
}

void slot_obs_append(struct Slots *pointer, struct Diagnostic *incoming) {
	int b = bag(pointer), e = element(incoming);
	struct Bag *state = &bags[b];
	assert(!state->dropping && state->length < state->capacity && state->length < 16 && elements[e].state == 1 && !elements[e].bag);
	assert(pointer->base == state->backing && pointer->capacity == state->capacity && pointer->length == state->length + 1 && pointer->base[state->length] == incoming);
	for (int i = 0; i < state->length; ++i)
		assert(state->elements[i] != incoming);
	stable(e);
	state->elements[state->length++] = incoming;
	elements[e].bag = b;
	printf("P%d index=%d element=%d\n", b, state->length - 1, e);
	flush();
}

void slot_obs_borrow(struct Slots *pointer, int32_t index, struct Diagnostic *entry) {
	int b = bag(pointer);
	struct Bag *state = &bags[b];
	assert(!state->dropping && index >= 0 && index < state->length && pointer->base == state->backing && pointer->base[index] == entry && state->elements[index] == entry);
	stable(element(entry));
	++borrow_count;
	printf("V%d index=%d element=%d\n", b, index, element(entry));
	flush();
}

void slot_obs_drop_begin(struct Slots *pointer) {
	int b = bag(pointer);
	struct Bag *state = &bags[b];
	assert(!state->dropping && pointer->base == state->backing && pointer->length == state->length && pointer->capacity == state->capacity);
	state->dropping = true;
	int id = allocation(state->backing);
	if (id) allocations[id].retiring = true;
	printf("D%d len=%d\n", b, state->length);
	flush();
}

void slot_obs_retire(struct Slots *pointer, int32_t index, struct Diagnostic *entry) {
	int b = bag(pointer), e = element(entry);
	struct Bag *state = &bags[b];
	assert(state->dropping && index == state->length - 1 && entry == state->elements[index] && pointer->length == index && !pointer->base[index]);
	assert(elements[e].bag == b && elements[e].state == 1);
	stable(e);
	elements[e].state = 2;
	--state->length;
	printf("R%d index=%d element=%d\n", b, index, e);
	flush();
}

void slot_obs_dying(struct Diagnostic *pointer) {
	int e = element(pointer);
	stable(e);
	assert(elements[e].state == 2);
	elements[e].state = 3;
	printf("E%d tag=%d\n", e, elements[e].tag);
	flush();
}

void slot_obs_drop_done(struct Slots *pointer) {
	int b = bag(pointer);
	struct Bag *state = &bags[b];
	assert(state->dropping && !state->length && !pointer->base && !pointer->length && !pointer->capacity);
	if (state->backing) {
		bool retired = false;
		for (int i = 1; i <= allocation_count; ++i)
			if (allocations[i].pointer == state->backing && !allocations[i].live) retired = true;
		assert(retired);
	}
	state->dropped = true;
	printf("Z%d\n", b);
	flush();
}

void slot_obs_done(void) {
	for (int i = 1; i <= allocation_count; ++i)
		assert(!allocations[i].live);
	for (int i = 1; i <= element_count; ++i)
		assert(elements[i].freed && elements[i].state == 3);
	for (int i = 1; i <= bag_count; ++i)
		assert(bags[i].dropped);
	printf("OK allocations=%d elements=%d growth=%d borrows=%d\n", allocation_count, element_count, growth_count, borrow_count);
	flush();
}
