// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Test-only allocation and descriptor observers. No exchange implementation.
#define _GNU_SOURCE
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static struct {
	unsigned char *base;
	size_t bytes, mapped, count, stride;
	int live;
} allocations[16384];
static int generation, frees, active, fail_next, token;
static void *addresses[4], *before[2];
static int32_t counts[2];
static int identities[2], saved_generation, saved_frees;
static uint64_t hashes[2];
static void *watched_addresses[4], *watched_bases[2];
static int32_t watched_counts[2];
static const uint32_t bits32[] = {0, 0x80000000, 1, 0x007fffff, 0x00800000, 0x3f800001, 0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc01234, 0xffc04321};
static const uint64_t bits64[] = {0, UINT64_C(0x8000000000000000), 1, UINT64_C(0x000fffffffffffff), UINT64_C(0x0010000000000000), UINT64_C(0x3ff0000000000001), UINT64_C(0x7fefffffffffffff), UINT64_C(0xffefffffffffffff), UINT64_C(0x7ff0000000000000), UINT64_C(0xfff0000000000000), UINT64_C(0x7ff8000000001234), UINT64_C(0xfff8000000004321)};

float se_f32(int32_t n) {
	assert(n >= 0 && n < 12);
	float v;
	memcpy(&v, bits32 + n, sizeof v);
	return v;
}
double se_f64(int32_t n) {
	assert(n >= 0 && n < 12);
	double v;
	memcpy(&v, bits64 + n, sizeof v);
	return v;
}
int32_t se_check32(float v, int32_t n) {
	uint32_t b;
	memcpy(&b, &v, sizeof b);
	return b == bits32[n];
}
int32_t se_check64(double v, int32_t n) {
	uint64_t b;
	memcpy(&b, &v, sizeof b);
	return b == bits64[n];
}
void *se_pointer(void) {
	return &token;
}
int32_t se_mark(int32_t n) {
	assert(!active);
	printf("M%d\n", n);
	fflush(stdout);
	return n;
}
void se_fail(void) {
	assert(!active);
	fail_next = 1;
}
void os_live(int32_t expected) {
	int live = 0;
	for (int i = 1; i <= generation; i++) {
		live += allocations[i].live;
	}
	assert(live == expected);
}

static int identify(void *base, int32_t count) {
	if (!count) {
		assert(!base);
		return 0;
	}
	assert(count > 0);
	for (int i = generation; i > 0; i--) {
		if (allocations[i].base == base && allocations[i].live) {
			assert(allocations[i].count == (size_t)count);
			return i;
		}
	}
	assert(!"descriptor does not name a legitimate live allocation");
	return -1;
}

static uint64_t hash(int identity) {
	uint64_t h = UINT64_C(1469598103934665603);
	// Object representation, including padding, is inspected as unsigned bytes.
	// No padding is read as an Astra value.
	for (size_t j = 0; j < allocations[identity].bytes; j++) {
		h = (h ^ allocations[identity].base[j]) * UINT64_C(1099511628211);
	}
	return h;
}

void *__wrap_calloc(size_t count, size_t stride) {
	assert(!active && count && stride && count <= SIZE_MAX / stride && generation < 16383);
	if (fail_next) {
		// The later replacement fixture is still in the swapped slots' scope.
		for (int j = 0; j < 2; j++) {
			void *p;
			int32_t n;
			memcpy(&p, addresses[j * 2], sizeof p);
			memcpy(&n, addresses[j * 2 + 1], sizeof n);
			assert(p == before[1 - j] && n == counts[1 - j]);
		}
		puts("OOM");
		fflush(stdout);
		return NULL;
	}
	size_t page = (size_t)sysconf(_SC_PAGESIZE), bytes = count * stride;
	size_t mapped = (bytes + page - 1) / page * page;
	void *base = mmap(NULL, mapped, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	assert(base != MAP_FAILED);
	int i = ++generation;
	allocations[i].base = base;
	allocations[i].bytes = bytes;
	allocations[i].mapped = mapped;
	allocations[i].count = count;
	allocations[i].stride = stride;
	allocations[i].live = 1;
	printf("A%d:%zu:%zu\n", i, count, stride);
	fflush(stdout);
	return base;
}

void __wrap_free(void *base) {
	assert(!active && base);
	for (int i = generation; i > 0; i--) {
		if (allocations[i].live && allocations[i].base == base) {
			allocations[i].live = 0;
			frees++;
			assert(munmap(base, allocations[i].mapped) == 0);
			printf("F%d\n", i);
			fflush(stdout);
			return;
		}
	}
	assert(!"duplicate or unknown cleanup");
}

// These hooks are inserted only in independent test LLVM, immediately outside
// each unchanged eight-instruction exchange. Slot components are private probes.
void os_before(void *lp, void *lc, void *rp, void *rc) {
	assert(!active);
	addresses[0] = lp;
	addresses[1] = lc;
	addresses[2] = rp;
	addresses[3] = rc;
	memcpy(before, lp, sizeof(void *));
	memcpy(before + 1, rp, sizeof(void *));
	memcpy(counts, lc, sizeof(int32_t));
	memcpy(counts + 1, rc, sizeof(int32_t));
	for (int i = 0; i < 2; i++) {
		identities[i] = identify(before[i], counts[i]);
		hashes[i] = hash(identities[i]);
	}
	assert((lp == rp && lc == rc) || !before[0] || !before[1] || before[0] != before[1]);
	saved_generation = generation;
	saved_frees = frees;
	for (int i = 1; i <= generation; i++) {
		if (allocations[i].live) {
			assert(mprotect(allocations[i].base, allocations[i].mapped, PROT_NONE) == 0);
		}
	}
	active = 1;
}

void os_after(void) {
	assert(active && saved_generation == generation && saved_frees == frees);
	for (int i = 1; i <= generation; i++) {
		if (allocations[i].live) {
			assert(mprotect(allocations[i].base, allocations[i].mapped, PROT_READ | PROT_WRITE) == 0);
		}
	}
	for (int i = 0; i < 2; i++) {
		void *base;
		int32_t count;
		memcpy(&base, addresses[i * 2], sizeof base);
		memcpy(&count, addresses[i * 2 + 1], sizeof count);
		assert(base == before[1 - i] && count == counts[1 - i]);
		assert(identify(base, count) == identities[1 - i]);
		assert(hash(identities[i]) == hashes[i]);
	}
	printf("X%d:%d:%d:%d\n", identities[0], counts[0], identities[1], counts[1]);
	fflush(stdout);
	active = 0;
}

void os_watch(void *lp, void *lc, void *rp, void *rc) {
	watched_addresses[0] = lp;
	watched_addresses[1] = lc;
	watched_addresses[2] = rp;
	watched_addresses[3] = rc;
	for (int i = 0; i < 2; i++) {
		memcpy(watched_bases + i, watched_addresses[2 * i], sizeof(void *));
		memcpy(watched_counts + i, watched_addresses[2 * i + 1], sizeof(int32_t));
	}
}

void os_layout(void *object, void *first, void *second) {
	printf("L%zu:%zu\n", (size_t)((uintptr_t)first - (uintptr_t)object), (size_t)((uintptr_t)second - (uintptr_t)object));
	fflush(stdout);
}

void os_trap(void) {
	assert(!active);
	for (int i = 0; i < 2; i++) {
		void *p;
		int32_t n;
		memcpy(&p, watched_addresses[2 * i], sizeof p);
		memcpy(&n, watched_addresses[2 * i + 1], sizeof n);
		assert(p == watched_bases[i] && n == watched_counts[i]);
	}
	puts("T-unchanged");
	fflush(stdout);
}

__attribute__((destructor)) static void complete(void) {
	assert(!active);
	os_live(0);
}
