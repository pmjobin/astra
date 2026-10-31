/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <limits.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
_Static_assert(CHAR_BIT == 8 && sizeof(int32_t) == 4 && INT32_MAX == 2147483647, "qualified C channels");
_Static_assert(sizeof(float) == 4 && sizeof(double) == 8, "qualified floating channels");
/* Owned by the harness, independently of incoming views. The readers never
 * retain a parameter or a derived alias. Only scalar observations survive. */
extern const unsigned char *expected_a, *expected_b;
extern int32_t expected_an, expected_bn;
extern const unsigned char *expected_a_bytes, *expected_b_bytes;
extern void *expected_token;
int observer_calls;
static void view(const unsigned char *data, int32_t count, const unsigned char *expected, int32_t length, const unsigned char *original) {
	assert(data == expected && count == length && count >= 0);
	for (int32_t i = 0; i < count; i++) {
		assert(data[i] == original[i]);
	}
}
int32_t unfamiliar_reader(int32_t tag, const unsigned char *a, int32_t an, float scale, const unsigned char *b, int32_t bn, double wide, void *token) {
	uint32_t f;
	uint64_t d;
	memcpy(&f, &scale, sizeof f);
	memcpy(&d, &wide, sizeof d);
	assert(tag == 17 && f == UINT32_C(0x3fc00000) && d == UINT64_C(0x8000000000000000));
	assert(token == expected_token);
	view(a, an, expected_a, expected_an, expected_a_bytes);
	view(b, bn, expected_b, expected_bn, expected_b_bytes);
	observer_calls++;
	return 23;
}
int32_t static_reader(const unsigned char *a, int32_t an, const unsigned char *b, int32_t bn) {
	static const unsigned char expected[] = {'S', 0, 0xc3, 0xa9};
	assert(a == b && an == 4 && bn == 4);
	for (int32_t i = 0; i < an; i++) {
		assert(a[i] == expected[i]);
	}
	return 0;
}
float float_reader(const unsigned char *a, int32_t an, float x, const unsigned char *b, int32_t bn) {
	view(a, an, expected_a, expected_an, expected_a_bytes);
	view(b, bn, expected_b, expected_bn, expected_b_bytes);
	return x;
}
double double_reader(const unsigned char *a, int32_t an, double x) {
	view(a, an, expected_a, expected_an, expected_a_bytes);
	return x;
}
void *pointer_reader(const unsigned char *a, int32_t an, void *token) {
	view(a, an, expected_a, expected_an, expected_a_bytes);
	assert(token == expected_token);
	return token;
}
void void_reader(const unsigned char *a, int32_t an) {
	view(a, an, expected_a, expected_an, expected_a_bytes);
	observer_calls++;
}
