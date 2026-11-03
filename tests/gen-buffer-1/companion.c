// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Reuse the qualified guarded allocator and exact floating bit oracle.
#include "../gen-slice-1/companion.c"

int32_t gb_word(int32_t index) {
	static const int32_t words[] = {INT32_MIN, INT32_MAX, -1, 0, 1, 127, -128, 255, 32767, -32768, 65535, 16777217};
	assert(index >= 0);
	return words[index % 12];
}

int32_t gb_generation(void) {
	return next_owner;
}

void gb_unchanged(int32_t generation) {
	assert(generation == next_owner);
}

void gb_zero(int32_t value) {
	assert(value == 0);
}

void gb_check_word(int32_t value, int32_t index) {
	assert(value == gb_word(index));
}

// Inspect allocation identity through the private allocator ledger. Astra has
// no new raw pointer operation. Each fresh live allocation must be distinct.
void gb_distinct(void) {
	for (int i = 1; i <= next_owner; i++) {
		if (!owners[i].live) {
			continue;
		}
		for (int j = 1; j < i; j++) {
			assert(!owners[j].live || owners[j].raw != owners[i].raw);
		}
	}
}

void gb_live(int32_t expected) {
	int count = 0;
	for (int i = 1; i <= next_owner; i++) {
		count += owners[i].live;
	}
	assert(count == expected);
}

// Called only by the independent LLVM entry observer, never by Astra source.
void gb_pair(void *base, int32_t count, int32_t identity, int32_t stride) {
	if (count == 0) {
		assert(base == NULL && identity == 0);
		return;
	}
	assert(identity > 0 && identity <= next_owner && owners[identity].live);
	assert(base == owners[identity].raw + 32 && owners[identity].bytes == (size_t)count * (size_t)stride);
}
