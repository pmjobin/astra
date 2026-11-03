// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Test-only observations of authentic emitted operations and real allocations.
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

_Static_assert(sizeof(struct Slots) == 16 && offsetof(struct Slots, length) == 8 && offsetof(struct Slots, capacity) == 12, "qualified descriptor");
_Static_assert(sizeof(struct Message) == 16 && offsetof(struct Diagnostic, message) == 8, "exact element layout");

enum Role { OTHER,
	        BAG,
	        BACKING,
	        ELEMENT,
	        CHILD,
	        PAYLOAD };

struct Allocation {
	void *pointer;
	size_t count, stride;
	enum Role role;
	bool live, retiring;
};

struct Element {
	void *pointer;
	struct Message *message;
	const unsigned char *bytes;
	int32_t length, tag;
	unsigned char snapshot[64];
	int kind, bag;
	bool retiring, freed;
};

struct Bag {
	struct Slots *pointer;
	void **backing;
	int elements[16], length, capacity, kind, growth;
	bool dropping, dropped;
};
static struct Allocation allocations[512];
static struct Element elements[64];
static struct Bag bags[16];
static int allocation_count, element_count, bag_count, borrows;
void *__real_malloc(size_t);
void *__real_calloc(size_t, size_t);
void __real_free(void *);

static void flush(void) {
	fflush(stdout);
}

static int allocation(void *pointer) {
	if (!pointer) return 0;
	for (int i = allocation_count; i; --i)
		if (allocations[i].live && allocations[i].pointer == pointer) return i;
	assert(!"not an actual live allocation");
	return 0;
}

static int bag(struct Slots *pointer) {
	for (int i = bag_count; i; --i)
		if (bags[i].pointer == pointer && !bags[i].dropped) return i;
	assert(!"unknown live bag");
	return 0;
}

static void role(void *pointer, enum Role value) {
	if (pointer) {
		int a = allocation(pointer);
		assert(allocations[a].role == OTHER);
		allocations[a].role = value;
	}
}

static void stable(int e) {
	struct Element *p = &elements[e];
	assert(!p->freed && allocation(p->pointer) && allocation(p->message));
	if (p->kind == 1) {
		struct Diagnostic *d = p->pointer;
		assert(d->tag == p->tag && d->message == p->message);
	}
	assert(p->message->bytes == p->bytes && p->message->length == p->length);
	if (p->bytes) assert(allocation((void *)p->bytes));
	assert(!p->length || !memcmp(p->snapshot, p->bytes, (size_t)p->length));
}

static void *record(void *pointer, size_t count, size_t stride) {
	assert(pointer && allocation_count + 1 < 512);
	int a = ++allocation_count;
	allocations[a] = (struct Allocation){pointer, count, stride, OTHER, true, false};
	printf("A%d %zu:%zu\n", a, count, stride);
	flush();
	return pointer;
}

void *__wrap_malloc(size_t bytes) {
	return record(__real_malloc(bytes), 1, bytes);
}

void *__wrap_calloc(size_t count, size_t stride) {
	if (count == 3 && stride == sizeof(void *) && getenv("GEN_BAG_FAIL_GROW")) {
		puts("OOM growth");
		flush();
		return NULL;
	}
	return record(__real_calloc(count, stride), count, stride);
}

void __wrap_free(void *pointer) {
	if (!pointer) {
		__real_free(pointer);
		return;
	}
	int a = allocation(pointer);
	enum Role purpose = allocations[a].role;
	if (purpose == BACKING) assert(allocations[a].retiring);
	if (purpose == BAG) {
		bool done = false;
		for (int b = 1; b <= bag_count; b++)
			if (bags[b].pointer == pointer && bags[b].dropped) done = true;
		assert(done);
	}
	if (purpose == ELEMENT || purpose == CHILD || purpose == PAYLOAD) {
		bool matched = false;
		for (int e = 1; e <= element_count; e++) {
			struct Element *p = &elements[e];
			if (p->freed) continue;
			if (pointer != p->pointer && pointer != (void *)p->message && pointer != (void *)p->bytes) continue;
			assert(p->retiring);
			matched = true;
			if (pointer == (void *)p->message && p->bytes) {
				for (int i = 1; i <= allocation_count; i++)
					if (allocations[i].pointer == (void *)p->bytes && allocations[i].role == PAYLOAD) assert(!allocations[i].live);
			}
			if (pointer == p->pointer) {
				if (p->kind == 1)
					for (int i = 1; i <= allocation_count; i++)
						if (allocations[i].pointer == p->message && allocations[i].role == CHILD) assert(!allocations[i].live);
				p->freed = true;
			}
		}
		assert(matched);
	}
	allocations[a].live = false;
	printf("F%d\n", a);
	flush();
	__real_free(pointer);
}

void bag_obs_init(int kind, struct Slots *pointer) {
	assert((kind == 1 || kind == 2) && bag_count + 1 < 16 && !pointer->base && !pointer->length && !pointer->capacity);
	int b = ++bag_count;
	bags[b] = (struct Bag){.pointer = pointer, .kind = kind};
	role(pointer, BAG);
	printf("B%d kind=%d object=%d\n", b, kind, allocation(pointer));
	flush();
}

void bag_obs_append(int kind, struct Slots *pointer, void *incoming) {
	int b = bag(pointer);
	struct Bag *p = &bags[b];
	assert(kind == p->kind && !p->dropping && p->length < p->capacity && p->length < 16 && element_count + 1 < 64);
	for (int i = 1; i <= element_count; i++)
		if (!elements[i].freed) assert(elements[i].pointer != incoming && elements[i].message != incoming);
	struct Message *message = kind == 1 ? ((struct Diagnostic *)incoming)->message : incoming;
	assert(message->length >= 0 && message->length < 64);
	int e = ++element_count;
	elements[e] = (struct Element){.pointer = incoming, .message = message, .bytes = message->bytes, .length = message->length, .kind = kind, .bag = b, .tag = kind == 1 ? ((struct Diagnostic *)incoming)->tag : 0};
	if (message->length) memcpy(elements[e].snapshot, message->bytes, (size_t)message->length);
	role(incoming, ELEMENT);
	if (kind == 1) role(message, CHILD);
	role((void *)message->bytes, PAYLOAD);
	assert(pointer->base == p->backing && pointer->capacity == p->capacity && pointer->length == p->length + 1 && pointer->base[p->length] == incoming);
	p->elements[p->length++] = e;
	stable(e);
	printf("P%d index=%d element=%d kind=%d object=%d message=%d bytes=%d\n", b, p->length - 1, e, kind, allocation(incoming), allocation(message), allocation((void *)message->bytes));
	flush();
}

void bag_obs_commit(int kind, struct Slots *pointer, void **old, void **replacement, int32_t length, int32_t capacity) {
	int b = bag(pointer);
	struct Bag *p = &bags[b];
	assert(kind == p->kind && !p->dropping && old == p->backing && replacement && replacement != old && length == p->length && capacity > p->capacity);
	assert(pointer->base == replacement && pointer->length == length && pointer->capacity == capacity);
	int a = allocation(replacement);
	assert(allocations[a].count == (size_t)capacity && allocations[a].stride == sizeof(void *));
	role(replacement, BACKING);
	for (int i = 0; i < length; i++) {
		assert(replacement[i] == elements[p->elements[i]].pointer && !old[i]);
		stable(p->elements[i]);
	}
	for (int i = length; i < capacity; i++)
		assert(!replacement[i]);
	int prior = allocation(old);
	if (prior) allocations[prior].retiring = true;
	if (p->capacity) p->growth++;
	printf("G%d kind=%d %d->%d len=%d old=%d new=%d\n", b, kind, p->capacity, capacity, length, prior, a);
	flush();
	p->backing = replacement;
	p->capacity = capacity;
}

void bag_obs_borrow(int kind, struct Slots *pointer, int32_t index, void *element) {
	int b = bag(pointer);
	struct Bag *p = &bags[b];
	assert(kind == p->kind && !p->dropping && index >= 0 && index < p->length && pointer->base == p->backing && pointer->base[index] == element && elements[p->elements[index]].pointer == element);
	stable(p->elements[index]);
	borrows++;
	printf("V%d index=%d element=%d\n", b, index, p->elements[index]);
	flush();
}

void bag_obs_drop_begin(int kind, struct Slots *pointer) {
	int b = bag(pointer);
	struct Bag *p = &bags[b];
	assert(kind == p->kind && !p->dropping && pointer->base == p->backing && pointer->length == p->length && pointer->capacity == p->capacity);
	p->dropping = true;
	if (p->backing) allocations[allocation(p->backing)].retiring = true;
	printf("D%d kind=%d len=%d\n", b, kind, p->length);
	flush();
}

void bag_obs_retire(int kind, struct Slots *pointer, int32_t index, void *element) {
	int b = bag(pointer);
	struct Bag *p = &bags[b];
	assert(kind == p->kind && p->dropping && index == p->length - 1 && index >= 0 && elements[p->elements[index]].pointer == element && pointer->length == index && !pointer->base[index]);
	int e = p->elements[index];
	stable(e);
	assert(!elements[e].retiring);
	elements[e].retiring = true;
	p->length--;
	printf("R%d kind=%d index=%d element=%d\n", b, kind, index, e);
	flush();
}

void bag_obs_drop_done(int kind, struct Slots *pointer) {
	int b = bag(pointer);
	struct Bag *p = &bags[b];
	assert(kind == p->kind && p->dropping && !p->length && !pointer->base && !pointer->length && !pointer->capacity);
	if (p->backing)
		for (int a = 1; a <= allocation_count; a++)
			if (allocations[a].pointer == p->backing && allocations[a].role == BACKING) assert(!allocations[a].live);
	p->dropped = true;
	printf("Z%d\n", b);
	flush();
}

void bag_obs_done(void) {
	int growth = 0;
	for (int b = 1; b <= bag_count; b++) {
		assert(bags[b].dropped);
		growth += bags[b].growth;
	}
	for (int e = 1; e <= element_count; e++)
		assert(elements[e].freed);
	for (int a = 1; a <= allocation_count; a++)
		assert(!allocations[a].live);
	printf("OK bags=%d elements=%d growth=%d borrows=%d\n", bag_count, element_count, growth, borrows);
	flush();
}
