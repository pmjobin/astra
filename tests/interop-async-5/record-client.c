/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "record-api.h"
#include <stddef.h>
#include <stdio.h>
#include <stdint.h>
_Static_assert(sizeof(struct RecordInts) == 16 && _Alignof(struct RecordInts) == 8 && offsetof(struct RecordInts, second) == 8, "integer layout");
_Static_assert(sizeof(struct RecordFloats) == 16 && _Alignof(struct RecordFloats) == 8 && offsetof(struct RecordFloats, second) == 8, "floating layout");
_Static_assert(sizeof(struct RecordMixed) == 16 && _Alignof(struct RecordMixed) == 8 && offsetof(struct RecordMixed, mean) == 8, "mixed layout");
_Static_assert(sizeof(struct RecordStack) == 24 && _Alignof(struct RecordStack) == 8 && offsetof(struct RecordStack, total) == 8 && offsetof(struct RecordStack, tag) == 16, "stack layout");
_Static_assert(sizeof(struct RecordPadded) == 16 && _Alignof(struct RecordPadded) == 8 && offsetof(struct RecordPadded, wide) == 8, "padded float/double layout");

int main(void) {
	uint64_t hash = 0;
	for (int64_t n = -127; n <= 128; n++) {
		struct RecordInts i = astra_record_ints((struct RecordInts){n, 3 - n});
		struct RecordFloats f = astra_record_floats((struct RecordFloats){(double)n / 4, (double)(7 - n) / 4});
		struct RecordMixed m = astra_record_mixed((struct RecordMixed){n, (double)(2 - n) / 4});
		struct RecordStack s = astra_record_stack((struct RecordStack){n, (double)(5 - n) / 4, n * 2});
		struct RecordPadded p = astra_record_padded((struct RecordPadded){(float)n / 4, (double)(1 - n) / 4});
		if (i.first != n * 3 + 10 || i.second != (3 - n) * 5 - 6 || f.first != (double)n / 2 + 2.5 || f.second != (double)(7 - n) / 2 + 0.5 || m.count != n + 4 || m.mean != (double)(2 - n) / 2 + 1 || s.count != (n + 1) * 2 || s.total != (double)(5 - n) / 4 + 2.25 || s.tag != n * 2 - 2 || p.narrow != (float)n / 2 + 0.5f || p.wide != (double)(1 - n) / 2 + 8) return 80;
		hash = hash * 33 + (uint64_t)i.first + (uint64_t)(int64_t)(f.first * 4) + (uint64_t)m.count + (uint64_t)s.tag + (uint64_t)(int64_t)(p.wide * 2);
	}
	printf("record-client: 1280 by-value roundtrips hash=%llu\n", (unsigned long long)hash);
	return 0;
}
