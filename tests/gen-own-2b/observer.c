// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include "../gen-own-2a/observer.c"

// Constructor instrumentation establishes identity; relay/sink entries must
// see that same live original pointer with their independently planned domain.
void own_forward_pointer(void *pointer, int32_t heap) {
	int found = -1;
	for (int id = 1; id < 128; id++) {
		if (owners[id].initialized && owners[id].pointer == pointer && !owners[id].observed && !owners[id].frees) {
			require(found == -1);
			found = id;
		}
	}
	require(found > 0);
	own_pointer(pointer, found, heap < 0 ? owners[found].heap : heap, 0);
}
