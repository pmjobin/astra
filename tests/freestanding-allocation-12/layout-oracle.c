/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

struct WireReading {
	uint8_t tag;
	int64_t timestamp;
	float gain;
	uint16_t count;
	double total;
	uint32_t flags;
};

_Static_assert(sizeof(struct WireReading) == 40, "C complete extent");
_Static_assert(_Alignof(struct WireReading) == 8, "C record alignment");
_Static_assert(offsetof(struct WireReading, tag) == 0, "C tag offset");
_Static_assert(offsetof(struct WireReading, timestamp) == 8, "C timestamp offset");
_Static_assert(offsetof(struct WireReading, gain) == 16, "C gain offset");
_Static_assert(offsetof(struct WireReading, count) == 20, "C count offset");
_Static_assert(offsetof(struct WireReading, total) == 24, "C total offset");
_Static_assert(offsetof(struct WireReading, flags) == 32, "C flags offset");

int32_t layout_oracle(struct WireReading *value) {
	if ((uintptr_t)value % _Alignof(struct WireReading) || value->tag != 7 ||
	    value->timestamp != INT64_C(4294967300) || value->gain != 1.25f || value->count != 6 ||
	    value->total != 42.0 || value->flags != UINT32_C(2147483649)) {
		return 0;
	}
	value->tag = 9;
	++value->timestamp;
	value->count *= 2;
	value->total *= 2;
	printf("C:size=%zu,align=%zu,offsets=0/8/16/20/24/32\n", sizeof(*value), _Alignof(struct WireReading));
	return 1;
}
