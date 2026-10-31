/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Independent all-C control for the equations in A36, linked with each provider. */
#include "record-api.h"
struct RecordInts astra_record_ints(struct RecordInts v) {
	struct RecordInts r = c_record_ints(v);
	r.first += 9;
	r.second -= 4;
	return r;
}
struct RecordFloats astra_record_floats(struct RecordFloats v) {
	struct RecordFloats r = c_record_floats(v);
	r.first *= 2;
	r.second += 0.5;
	return r;
}
struct RecordMixed astra_record_mixed(struct RecordMixed v) {
	struct RecordMixed r = c_record_mixed(v);
	r.count += 11;
	r.mean *= 2;
	return r;
}
struct RecordStack astra_record_stack(struct RecordStack v) {
	struct RecordStack r = c_record_stack(v);
	r.count *= 2;
	r.total += 0.25;
	r.tag -= 5;
	return r;
}
struct RecordPadded astra_record_padded(struct RecordPadded v) {
	struct RecordPadded r = c_record_padded(v);
	r.narrow += 0.5f;
	r.wide *= 2;
	return r;
}
