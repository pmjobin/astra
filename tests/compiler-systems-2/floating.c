/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <string.h>
float input32(int index) {
	const uint32_t bits[] = {0x3f800001, 0x3f7ffffe, 0xbf800000, 0x80000000, 0, 0x7fc01234, 1};
	float result;
	memcpy(&result, &bits[index], sizeof result);
	return result;
}
double input64(int index) {
	const uint64_t bits[] = {UINT64_C(0x3ff0000000000001), UINT64_C(0x3feffffffffffffe), UINT64_C(0xbff0000000000000), UINT64_C(0x8000000000000000), 0, UINT64_C(0x7ff8000000001234), 1};
	double result;
	memcpy(&result, &bits[index], sizeof result);
	return result;
}
int observe32(int tag, float value) {
	const uint32_t expected[] = {0, 0x80000000, 0xff800000, 2};
	uint32_t bits;
	memcpy(&bits, &value, sizeof bits);
	return bits != expected[tag];
}
int observe64(int tag, double value) {
	const uint64_t expected[] = {0, UINT64_C(0x8000000000000000), UINT64_C(0xfff0000000000000), 2};
	uint64_t bits;
	memcpy(&bits, &value, sizeof bits);
	return bits != expected[tag];
}
#ifdef ASTRA_FLOAT_CLIENT
extern float astra_noncontract32(float, float, float);
extern double astra_noncontract64(double, double, double);
int main(void) {
	return observe32(0, astra_noncontract32(input32(0), input32(1), input32(2))) || observe64(0, astra_noncontract64(input64(0), input64(1), input64(2)));
}
#endif
