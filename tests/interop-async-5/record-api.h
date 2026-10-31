/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_SURGE5_RECORD_API_H
#define ASTRA_SURGE5_RECORD_API_H
#include <stdint.h>
struct RecordInts {
	int64_t first, second;
};
struct RecordFloats {
	double first, second;
};
struct RecordMixed {
	int64_t count;
	double mean;
};
struct RecordStack {
	int64_t count;
	double total;
	int64_t tag;
};
struct RecordPadded {
	float narrow;
	double wide;
};
#define RECORD_DECL(T, suffix) struct T c_record_##suffix(struct T); struct T astra_record_##suffix(struct T)
RECORD_DECL(RecordInts, ints);
RECORD_DECL(RecordFloats, floats);
RECORD_DECL(RecordMixed, mixed);
RECORD_DECL(RecordStack, stack);
RECORD_DECL(RecordPadded, padded);
#endif
