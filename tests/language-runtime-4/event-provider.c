/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stddef.h>

struct event_state {
	int64_t checksum;
	int32_t received;
	int32_t mode;
	int32_t count;
};

_Static_assert(sizeof(struct event_state) == 24 && _Alignof(struct event_state) == 8, "LP64 event state");
_Static_assert(offsetof(struct event_state, received) == 8, "event count offset");
_Static_assert(offsetof(struct event_state, mode) == 12 && offsetof(struct event_state, count) == 16, "event mode and limit offsets");
typedef int32_t (*event_callback)(struct event_state *, int32_t);

int32_t surge4_events(event_callback callback, struct event_state *state, int32_t first) {
	if (!callback || !state || state->received != 0 || state->checksum != 0) return -1;
	if (state->count < 0 || state->count > 1000 || state->mode < 0 || state->mode > 1) return -3;
	for (int32_t index = 0; index < state->count; ++index) {
		if (callback(state, first + index) != index + 1 || state->received != index + 1) return -2;
	}
	return state->count;
}
