// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Input and independent bit oracle only; the transform executes in Astra.
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef VIEW18_FLOAT32
typedef float sample_t;
typedef uint32_t sample_bits_t;
#else
typedef double sample_t;
typedef uint64_t sample_bits_t;
#endif

static int setting(const char *name, int maximum) {
	const char *text = getenv(name);
	if (!text) return 0;
	char *end;
	long value = strtol(text, &end, 10);
	if (*end || value < 0 || value > maximum) abort();
	return (int)value;
}

int view18_count(void) {
	return setting("VIEW18_COUNT", 8);
}

int view18_overlap(void) {
	return setting("VIEW18_OVERLAP", 1);
}

int view18_short(void) {
	return setting("VIEW18_SHORT", 1);
}

sample_t view18_input(int index) {
#ifdef VIEW18_FLOAT32
	static const sample_bits_t patterns[] = {
	    UINT32_C(0x00000000), UINT32_C(0x80000000),
	    UINT32_C(0x3fa00000), UINT32_C(0xc0200000),
	    UINT32_C(0x00000001), UINT32_C(0x80000001),
	    UINT32_C(0x7f800000), UINT32_C(0xff800000),
	    UINT32_C(0x7fc01234), UINT32_C(0xffc05678),
	    UINT32_C(0x00800000), UINT32_C(0x80800000),
	    UINT32_C(0x3f000000), UINT32_C(0xbf000000),
	    UINT32_C(0x40000000), UINT32_C(0xc0000000)};
#else
	static const uint64_t patterns[] = {
	    UINT64_C(0x0000000000000000), UINT64_C(0x8000000000000000),
	    UINT64_C(0x3ff4000000000000), UINT64_C(0xc004000000000000),
	    UINT64_C(0x0000000000000001), UINT64_C(0x8000000000000001),
	    UINT64_C(0x7ff0000000000000), UINT64_C(0xfff0000000000000),
	    UINT64_C(0x7ff8000000001234), UINT64_C(0xfff8000000005678),
	    UINT64_C(0x0010000000000000), UINT64_C(0x8010000000000000),
	    UINT64_C(0x3fe0000000000000), UINT64_C(0xbfe0000000000000),
	    UINT64_C(0x4000000000000000), UINT64_C(0xc000000000000000)};
#endif
	sample_bits_t bits = patterns[((unsigned)index + (unsigned)setting("VIEW18_SEED", 15)) % 16];
	sample_t value;
	memcpy(&value, &bits, sizeof value);
	return value;
}

static uint64_t bits(sample_t value) {
	sample_bits_t result;
	memcpy(&result, &value, sizeof result);
	return result;
}

static sample_t product(sample_t input, sample_t factor) {
	volatile sample_t result = input * factor;
	return result;
}

int view18_check(int index, sample_t value) {
	sample_t expected;
	if (index >= 100) {
		expected = product(view18_input(index - 100), 1.5);
	} else if (!view18_overlap()) {
		expected = product(view18_input(index), 1.75);
	} else {
		sample_t memory[12];
		for (int i = 0; i < 12; i++)
			memory[i] = view18_input(i);
		int i = 0, count = view18_count();
		// A complete vector load precedes the overlapping store. Scalar tails
		// follow the prior block's writes, with no restrict assumption.
		for (; i + 2 <= count; i += 2) {
			sample_t first = memory[i], second = memory[i + 1];
			memory[i + 1] = product(first, 1.75);
			memory[i + 2] = product(second, 1.75);
		}
		if (i < count) memory[i + 1] = product(memory[i], 1.75);
		expected = memory[index + 1];
	}
	if (bits(value) == bits(expected)) return 0;
	fprintf(stderr, "index=%d actual=%016" PRIx64 " expected=%016" PRIx64 "\n", index, bits(value), bits(expected));
	return 1;
}
