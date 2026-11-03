/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Deliberately nonconforming provider: a stale acknowledgement cannot authorize
 * native environment destruction. Only used in an expected-trap child. */
#define astra_retained_retire astra_retained_real_retire
#include "../../lib/runtime/interop/retained.c"
#undef astra_retained_retire

int32_t astra_retained_retire(void *token) {
	(void)token;
	return astra_retained_observe((void *)999999) == 1;
}
