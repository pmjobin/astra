/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <limits.h>
#include <xmmintrin.h>

static uint64_t state = UINT64_C(0x950acd3e617249bf);
static uint64_t next(void) {
	state ^= state << 13;
	state ^= state >> 7;
	state ^= state << 17;
	return state;
}

#ifdef ORACLE_F64
extern double filter_pair(double, double, double, double, double, double, int32_t);
extern double divide_pair(double, double, double, double, int32_t);
static double number(uint64_t bits) {
	double value;
	memcpy(&value, &bits, 8);
	return value;
}
static uint64_t bits(double value) {
	uint64_t result;
	memcpy(&result, &value, 8);
	return result;
}
static void same(double observed, double expected) {
	if (isnan(expected)) {
		assert(isnan(observed));
	} else {
		assert(bits(observed) == bits(expected));
	}
}
int32_t f64_oracle(void) {
	assert((_mm_getcsr() & ((1U << 15) | (1U << 6) | (3U << 13))) == 0);
	static const uint64_t edges[] = {0, UINT64_C(0x8000000000000000), 1,
	                                 UINT64_C(0x8000000000000001), UINT64_C(0x0010000000000000),
	                                 UINT64_C(0x3ff0000000000000), UINT64_C(0xbff0000000000000),
	                                 UINT64_C(0x7fefffffffffffff), UINT64_C(0x7ff0000000000000),
	                                 UINT64_C(0xfff0000000000000), UINT64_C(0x7ff8000000000123)};
	for (int i = 0; i < 2048; i++) {
		double a[2], gain[2], bias[2];
		for (int lane = 0; lane < 2; lane++) {
			a[lane] = number(i < 121 ? edges[(i + lane) % 11] : next());
			gain[lane] = number(i < 121 ? edges[(i / 11 + lane) % 11] : next());
			bias[lane] = number(i < 121 ? edges[(i * 3 + lane) % 11] : next());
		}
		for (int lane = 0; lane < 2; lane++) {
			volatile double product = a[lane] * gain[lane];
			volatile double expected = product + bias[lane];
			same(filter_pair(a[0], a[1], gain[0], gain[1], bias[0], bias[1], lane), expected);
			volatile double quotient = a[lane] / gain[lane];
			same(divide_pair(a[0], a[1], gain[0], gain[1], lane), quotient);
		}
	}
	puts("f64x2:2048 vectors;8192 exact lanes;NaNs classified");
	return 0;
}
#endif

#ifdef ORACLE_INTEGER
extern int64_t mix_wide(int64_t, int64_t, int32_t, int32_t);
extern uint64_t mix_unsigned(uint64_t, uint64_t, int32_t, int32_t);
extern int32_t pcm_mix(int32_t, int32_t);
static int64_t clamp_signed(__int128 value) {
	return value > INT64_MAX ? INT64_MAX : value < INT64_MIN ? INT64_MIN
	                                                         : (int64_t)value;
}
int32_t integer_oracle(void) {
	static const int64_t edges[] = {INT64_MIN, INT64_MAX, -1, 0, 1, -32768, 32767};
	for (int i = 0; i < 2048; i++) {
		int64_t a, b;
		uint64_t ua = next(), ub = next();
		if (i < 49) {
			a = edges[i % 7];
			b = edges[i / 7];
			ua = (uint64_t)a;
			ub = (uint64_t)b;
		} else {
			memcpy(&a, &ua, 8);
			memcpy(&b, &ub, 8);
		}
		assert(mix_wide(a, b, 0, 0) == clamp_signed((__int128)a + b));
		assert(mix_wide(a, b, 1, 0) == clamp_signed((__int128)a - b));
		assert(mix_wide(a, b, 0, 1) == clamp_signed((__int128)b + a));
		assert(mix_wide(a, b, 1, 1) == clamp_signed((__int128)b - a));
		unsigned __int128 sum = (unsigned __int128)ua + ub;
		assert(mix_unsigned(ua, ub, 0, 0) == (sum > UINT64_MAX ? UINT64_MAX : (uint64_t)sum));
		assert(mix_unsigned(ua, ub, 1, 0) == (ua < ub ? 0 : ua - ub));
		assert(mix_unsigned(ua, ub, 0, 1) == (sum > UINT64_MAX ? UINT64_MAX : (uint64_t)sum));
		assert(mix_unsigned(ua, ub, 1, 1) == (ub < ua ? 0 : ub - ua));
		int32_t pa = (int16_t)ua, pb = (int16_t)ub, pcm = pa + pb;
		pcm = pcm > 32767 ? 32767 : pcm < -32768 ? -32768
		                                         : pcm;
		assert(pcm_mix(pa, pb) == pcm);
	}
	puts("saturation:2048 pairs;signed64,unsigned64,PCM16 exact");
	return 0;
}
#endif
