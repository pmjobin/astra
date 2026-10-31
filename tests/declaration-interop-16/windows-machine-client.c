/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <windows.h>
#include <xmmintrin.h>
#include <stdbool.h>
#include <stdint.h>
#include <float.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>
#ifdef USE_SDK
#include "machine16.h"
#else
typedef struct machine16_handle machine16_handle;
typedef struct astra_foreign_error {
	int32_t domain, code;
} astra_foreign_error;
extern int32_t machine16_create(machine16_handle **, astra_foreign_error *);
extern int32_t machine16_half32(machine16_handle *, float, float *, astra_foreign_error *);
extern int32_t machine16_half64(machine16_handle *, double, double *, astra_foreign_error *);
extern int32_t machine16_flip(machine16_handle *, bool, bool *, astra_foreign_error *);
extern int32_t machine16_signed64(machine16_handle *, int64_t, int64_t *, astra_foreign_error *);
extern int32_t machine16_unsigned64(machine16_handle *, uint64_t, uint64_t *, astra_foreign_error *);
extern int32_t machine16_destroy(machine16_handle **, astra_foreign_error *);
#endif
_Static_assert(sizeof(void *) == 8 && sizeof(long) == 4 && sizeof(bool) == 1, "Windows x64 LLP64 and C99 bool");
_Static_assert(sizeof(float) == 4 && sizeof(double) == 8 && FLT_RADIX == 2 && FLT_MANT_DIG == 24 && DBL_MANT_DIG == 53, "IEEE binary32/binary64");
static float from32(uint32_t bits) {
	float value;
	memcpy(&value, &bits, sizeof value);
	return value;
}
static double from64(uint64_t bits) {
	double value;
	memcpy(&value, &bits, sizeof value);
	return value;
}
int main(void) {
	unsigned mxcsr = _mm_getcsr();
	assert((mxcsr & (UINT32_C(1) << 15 | UINT32_C(1) << 6 | UINT32_C(3) << 13)) == 0);
	machine16_handle *root = NULL;
	astra_foreign_error error = {0, 0};
	assert(machine16_create(&root, &error) == 0 && root);
	const uint32_t inputs32[] = {UINT32_C(0x00800000), UINT32_C(0x00000002), UINT32_C(0x80000002)};
	const uint32_t expected32[] = {UINT32_C(0x00400000), UINT32_C(0x00000001), UINT32_C(0x80000001)};
	for (unsigned i = 0; i < 3; ++i) {
		float value = 0;
		uint32_t bits = 0;
		assert(machine16_half32(root, from32(inputs32[i]), &value, &error) == 0);
		memcpy(&bits, &value, sizeof bits);
		assert(bits == expected32[i] && error.domain == 0 && error.code == 0);
	}
	const uint64_t inputs64[] = {UINT64_C(0x0010000000000000), UINT64_C(0x0000000000000002), UINT64_C(0x8000000000000002)};
	const uint64_t expected64[] = {UINT64_C(0x0008000000000000), UINT64_C(0x0000000000000001), UINT64_C(0x8000000000000001)};
	for (unsigned i = 0; i < 3; ++i) {
		double value = 0;
		uint64_t bits = 0;
		assert(machine16_half64(root, from64(inputs64[i]), &value, &error) == 0);
		memcpy(&bits, &value, sizeof bits);
		assert(bits == expected64[i]);
	}
	bool flag = false;
	assert(machine16_flip(root, false, &flag, &error) == 0 && flag);
	assert(machine16_flip(root, true, &flag, &error) == 0 && !flag);
	int64_t signed_value = 0;
	uint64_t unsigned_value = 0;
	assert(machine16_signed64(root, INT64_C(-5000000000), &signed_value, &error) == 0 && signed_value == INT64_C(-4999999993));
	assert(machine16_unsigned64(root, UINT64_C(9223372036854775809), &unsigned_value, &error) == 0 && unsigned_value == UINT64_C(9223372036854775816));
	assert(machine16_destroy(&root, &error) == 0 && !root);
	assert(HeapValidate(GetProcessHeap(), 0, NULL));
	printf("Windows MXCSR=0x%x; process heap integrity checked\n", mxcsr);
	puts("PASS Windows LLP64 scalar ABI, gradual underflow and heap integrity");
	return 0;
}
