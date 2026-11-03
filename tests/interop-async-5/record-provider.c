/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "record-api.h"
#include <inttypes.h>
#include <stdio.h>

struct RecordInts c_record_ints(struct RecordInts v) {
	return (struct RecordInts){v.first * 3 + 1, v.second * 5 - 2};
}

struct RecordFloats c_record_floats(struct RecordFloats v) {
	return (struct RecordFloats){v.first + 1.25, v.second * 2};
}

struct RecordMixed c_record_mixed(struct RecordMixed v) {
	return (struct RecordMixed){v.count - 7, v.mean + 0.5};
}

struct RecordStack c_record_stack(struct RecordStack v) {
	return (struct RecordStack){v.count + 1, v.total + 2, v.tag + 3};
}

struct RecordPadded c_record_padded(struct RecordPadded v) {
	return (struct RecordPadded){v.narrow * 2, v.wide + 4};
}

int c_record_report(int64_t hash) {
	if (hash != 1426) {
		fprintf(stderr, "bad record hash: %" PRId64 "\n", hash);
		return 91;
	}
	printf("record-diagnostics hash=%" PRId64 "\n", hash);
	return 0;
}
