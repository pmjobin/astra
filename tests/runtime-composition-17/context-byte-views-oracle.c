/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "context-provider.h"
#include <assert.h>
#include <stdio.h>

static void *payload;
static uint64_t origin_tag;
static unsigned released, observed;
extern int context_byte_views_run(void);
extern void *__real_astra_context17_allocate_mode(AstraContext17 *, uint64_t,
                                                  uint64_t, uint32_t, uint64_t, uint32_t);
extern int __real_astra_context17_release_origin_checked(void *, uint64_t);

void *__wrap_astra_context17_allocate_mode(AstraContext17 *context, uint64_t count,
                                           uint64_t size, uint32_t alignment, uint64_t tag, uint32_t mode) {
	assert(payload == NULL && count == 37 && size == 1 && mode == 2 && tag != 0);
	payload = __real_astra_context17_allocate_mode(context, count, size, alignment, tag, mode);
	assert(payload && astra_context17_origin(payload, tag) == context);
	origin_tag = tag;
	return payload;
}

int __wrap_astra_context17_release_origin_checked(void *pointer, uint64_t tag) {
	assert(pointer == payload && tag == origin_tag && released++ == 0 && observed == 1);
	return __real_astra_context17_release_origin_checked(pointer, tag);
}

int context_byte_view_observe(unsigned char *bytes, int count) {
	assert(bytes == payload && count == 37 && observed++ == 0 && released == 0);
	AstraContext17 *context = astra_context17_origin(bytes, origin_tag);
	AstraContext17Snapshot state;
	assert(astra_context17_snapshot(context, &state) == ASTRA_CONTEXT17_OK);
	assert(state.closed && state.anchors == 0 && state.live == 1);
	assert(bytes[0] == 17 && bytes[36] == 29);
	bytes[0] = 19;
	bytes[36] = 31;
	return 46;
}

int context_byte_views_finish(void) {
	assert(released == 1 && observed == 1 && m17_custom_provider_retired() == 1);
	puts("context byte views: exact nonescaping Astra/C storage, closed anchor and original final release");
	return 0;
}

int main(void) {
	return context_byte_views_run();
}
