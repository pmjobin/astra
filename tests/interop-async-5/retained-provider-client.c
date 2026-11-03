/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "../../lib/runtime/interop/retained.h"
#include <assert.h>
#include <stdio.h>

struct capture {
	int calls;
	int total;
	void *token;
};

static int32_t callback(void *context, int32_t input) {
	struct capture *capture = context;
	++capture->calls;
	capture->total += input;
	assert(astra_retained_dispatch(capture->token, 1) == -2); /* no reentry */
	assert(astra_retained_observe(capture->token) == 0);      /* cannot observe active */
	assert(astra_retained_retire(capture->token) == 0);       /* cannot free active */
	if (input == 7) {
		assert(astra_retained_revoke(capture->token) == 1);
		assert(astra_retained_observe(capture->token) == 0);
		assert(astra_retained_retire(capture->token) == 0);
	}
	return capture->total;
}

int main(void) {
	struct capture first = {0, 10, NULL}, second = {0, 20, NULL};
	assert(astra_retained_dispatch((void *)999999, 1) == -3);
	assert(astra_retained_revoke((void *)999999) == -3);
	assert(astra_retained_observe((void *)999999) == -3);
	assert(astra_retained_register(callback, &first, 1) == NULL);
	first.token = astra_retained_register(callback, &first, 0);
	second.token = astra_retained_register(callback, &second, 0);
	assert(first.token && second.token && first.token != second.token);
	assert(first.calls == 0 && second.calls == 0);
	assert(astra_retained_dispatch(first.token, 3) == 13);
	assert(astra_retained_dispatch(second.token, 7) == 27);
	assert(first.calls == 1 && second.calls == 1);
	assert(astra_retained_dispatch(second.token, 10) == -2);
	assert(astra_retained_observe(second.token) == 1);
	assert(astra_retained_observe(second.token) == 1);
	void *stale = second.token;
	assert(astra_retained_retire(second.token) == 1);
	assert(astra_retained_dispatch(stale, 1) == -3);
	assert(astra_retained_observe(stale) == -3);
	assert(astra_retained_retire(stale) == 0);
	assert(astra_retained_retire(first.token) == 1);
	for (int i = 0; i < 1000; ++i) {
		void *token = astra_retained_register(callback, &first, 0);
		assert(token && token != stale);
		assert(astra_retained_retire(token) == 1);
		assert(astra_retained_observe(stale) == -3);
	}
	void *capacity[64];
	for (size_t i = 0; i < 64; ++i) {
		capacity[i] = astra_retained_register(callback, &first, 0);
		assert(capacity[i]);
		for (size_t j = 0; j < i; ++j)
			assert(capacity[j] != capacity[i]);
	}
	assert(astra_retained_register(callback, &first, 0) == NULL);
	for (size_t i = 0; i < 64; ++i)
		assert(astra_retained_retire(capacity[i]) == 1);
	puts("retained-provider calls=2 identity=stable stale=rejected quiesced=2");
	return 0;
}
