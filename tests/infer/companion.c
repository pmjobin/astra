// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Reuse the accepted test-only allocation/resource trace and leak oracle.
#include "../buffer/companion.c"

double inf_double(void) {
	return 0x1.0000000000001p0;
}

double inf_vapi_double(void) {
	return inf_double();
}

float inf_float(void) {
	return 1.5f;
}

int32_t inf_bits64(double value, int32_t high, int32_t low) {
	uint64_t bits;
	memcpy(&bits, &value, sizeof bits);
	return bits == ((uint64_t)(uint32_t)high << 32 | (uint32_t)low);
}

int32_t inf_bits32(float value, int32_t expected) {
	uint32_t bits;
	memcpy(&bits, &value, sizeof bits);
	return bits == (uint32_t)expected;
}
