/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Test-only, authentic builder/message allocation observer plus Bag identity. */
#include "../text-own-1b/observer.c"

struct slots {
	void **base;
	int32_t length, capacity;
};

_Static_assert(sizeof(struct slots) == 16 && offsetof(struct slots, length) == 8,
               "qualified LP64 Bag slot descriptor");
static struct slots *bag_object;
static void **bag_base, **retired;
static void *bag_elements[16];
static int bag_length, bag_capacity, bag_dropping, bag_dropped, bag_growths;

static void bag_stable(struct slots *bag) {
	require(bag == bag_object && live(bag) && !bag_dropped);
	require(bag->base == bag_base && bag->length == bag_length && bag->capacity == bag_capacity);
	if (retired) {
		require(!live(retired));
		retired = NULL;
	}
	stable_messages();
}

void bag_obs_init(int32_t kind, struct slots *bag) {
	require(kind == 1 && !bag_object && extent(bag) == sizeof(*bag));
	require(!bag->base && !bag->length && !bag->capacity);
	bag_object = bag;
}

void bag_obs_commit(int32_t kind, struct slots *bag, void **old, void **replacement, int32_t length, int32_t capacity) {
	require(kind == 1 && bag == bag_object && old == bag_base && length == bag_length);
	require(replacement && replacement != old && capacity > bag_capacity && extent(replacement) == (size_t)capacity * sizeof(void *));
	require(bag->base == replacement && bag->length == length && bag->capacity == capacity);
	for (int i = 0; i < length; i++) {
		require(replacement[i] == bag_elements[i] && !old[i]);
	}
	for (int i = length; i < capacity; i++) {
		require(!replacement[i]);
	}
	if (bag_capacity == 2 && capacity == 3) {
		require(length == 2);
		bag_growths++;
		puts("bag-growth 2->3 len=2");
	}
	retired = old;
	bag_base = replacement;
	bag_capacity = capacity;
	stable_messages();
}

void bag_obs_append(int32_t kind, struct slots *bag, void *incoming) {
	require(kind == 1 && bag == bag_object && bag_length < 16 && bag->length == bag_length + 1);
	require(bag->base == bag_base && bag->base[bag_length] == incoming && live(incoming));
	for (int i = 0; i < bag_length; i++) {
		require(bag_elements[i] != incoming);
	}
	bag_elements[bag_length++] = incoming;
	bag_stable(bag);
}

void bag_obs_borrow(int32_t kind, struct slots *bag, int32_t index, void *entry) {
	require(kind == 1);
	bag_stable(bag);
	require(index >= 0 && index < bag_length && entry == bag_elements[index] && live(entry));
}

void bag_obs_drop_begin(int32_t kind, struct slots *bag) {
	require(kind == 1 && !bag_dropping);
	bag_stable(bag);
	bag_dropping = 1;
}

void bag_obs_retire(int32_t kind, struct slots *bag, int32_t index, void *entry) {
	require(kind == 1 && bag == bag_object && bag_dropping && index == bag_length - 1);
	require(bag->length == index && !bag->base[index] && entry == bag_elements[index] && live(entry));
	bag_length--;
	printf("bag-retire %d\n", index);
	stable_messages();
}

void bag_obs_drop_done(int32_t kind, struct slots *bag) {
	require(kind == 1 && bag == bag_object && bag_dropping && !bag_length);
	require(!bag->base && !bag->length && !bag->capacity && !live(bag_base));
	bag_dropped = 1;
}

void bag_obs_done(void) {
	require(bag_dropped && bag_growths == 1 && !live(bag_object) && !live(bag_base));
	puts("bag-observer: growth=1 reverse=3 drops=1");
}
