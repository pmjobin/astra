// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include "../infer/companion.c"

void *gi_token(int32_t id) {
	return bb_resource(id);
}
