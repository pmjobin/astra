/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdlib.h>
#include <stddef.h>
static int live, destroyed;
int32_t surge_event(int32_t stage, int32_t tag) {
	(void)tag;
	if (stage == 1)
		++live;
	else if (stage == 2) {
		if (live <= 0) abort();
		--live;
		++destroyed;
	} else
		abort();
	return live;
}
int32_t surge_live(void) {
	return live;
}
int32_t surge_destroyed(void) {
	return destroyed;
}

struct Shipment {
	uint8_t tag;
	int64_t total;
	size_t count;
};
_Static_assert(sizeof(struct Shipment) == 24 && _Alignof(struct Shipment) == 8, "Shipment extent");
_Static_assert(offsetof(struct Shipment, tag) == 0 && offsetof(struct Shipment, total) == 8 && offsetof(struct Shipment, count) == 16, "Shipment offsets");
int32_t surge_record_apply(struct Shipment *record, int32_t price) {
	if (!record || record->tag != 17 || price < 0 || price > 1000 || record->count > 1000) return -1;
	record->total += (int64_t)price * (int64_t)record->count;
	record->tag = 18;
	return 0;
}
struct Fold {
	int64_t total;
	int32_t invocations, bias, limit;
};
_Static_assert(sizeof(struct Fold) == 24 && _Alignof(struct Fold) == 8, "Fold extent");
_Static_assert(offsetof(struct Fold, total) == 0 && offsetof(struct Fold, invocations) == 8 && offsetof(struct Fold, bias) == 12 && offsetof(struct Fold, limit) == 16, "Fold offsets");
int32_t surge_fold(int32_t (*callback)(void *, int32_t), struct Fold *state, int32_t input) {
	if (!callback || !state || state->limit < 0 || state->limit > 1000) return -1;
	for (int32_t i = 0; i < state->limit; ++i) {
		if (callback(state, input + i) != i + 1) return -2;
	}
	return state->invocations;
}
