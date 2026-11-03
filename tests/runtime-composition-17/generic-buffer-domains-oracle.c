/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "../../lib/runtime/runtime/context-17.h"
#include <assert.h>
#include <stdio.h>

static AstraContext17 *contexts[3];
static void *payloads[3];
static uint64_t tags[3];
static unsigned acquired, released, modes;
extern void *__real_astra_context17_allocate_mode(AstraContext17 *, uint64_t,
                                                  uint64_t, uint32_t, uint64_t, uint32_t);
extern int __real_astra_context17_release_origin_checked(void *, uint64_t);

void *__wrap_astra_context17_allocate_mode(AstraContext17 *context, uint64_t count,
                                           uint64_t size, uint32_t alignment, uint64_t tag, uint32_t mode) {
	static const uint64_t lengths[] = {17, 19, 23};
	static const uint32_t expected_modes[] = {2, 0, 1};
	assert(acquired < 3 && size == 1 && count == lengths[acquired]);
	assert(mode == expected_modes[acquired] && (modes & (1U << mode)) == 0);
	void *payload = __real_astra_context17_allocate_mode(context, count, size, alignment, tag, mode);
	assert(payload != NULL && astra_context17_origin(payload, tag) == context);
	for (unsigned i = 0; i < acquired; ++i) {
		assert(contexts[i] != context && payloads[i] != payload && tags[i] != tag);
	}
	for (uint64_t i = 0; i < count; ++i) {
		assert(((unsigned char *)payload)[i] == 0);
	}
	contexts[acquired] = context;
	payloads[acquired] = payload;
	tags[acquired++] = tag;
	modes |= 1U << mode;
	return payload;
}

int __wrap_astra_context17_release_origin_checked(void *payload, uint64_t tag) {
	unsigned index = 0;
	while (index < acquired && payloads[index] != payload) {
		++index;
	}
	assert(index < acquired && tags[index] == tag && astra_context17_origin(payload, tag) == contexts[index]);
	AstraContext17Snapshot state;
	assert(astra_context17_snapshot(contexts[index], &state) == ASTRA_CONTEXT17_OK);
	assert(state.closed == 1 && state.anchors == 0 && state.live != 0);
	payloads[index] = NULL;
	int result = __real_astra_context17_release_origin_checked(payload, tag);
	assert(result == 1);
	++released;
	return result;
}

int buffer_domains_finish(void) {
	assert(acquired == 3 && released == 3 && modes == 7);
	puts("generic buffer domains: three allocator modes, borrowed views and exact closed-origin releases");
	return 0;
}

extern int buffer_domains_run(void);

int main(void) {
	return buffer_domains_run();
}
