/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "counter.h"
#include "gobject-signals.h"
#include "retained.h"
#include <assert.h>
#include <stdio.h>

struct capture {
	void *object;
	void *registration;
	int calls;
};

static void finalizing(gpointer data, GObject *object) {
	(void)object;
	struct capture *capture = data;
	assert(astra_retained_retire(capture->registration) == 0);
	assert(astra_retained_revoke(capture->registration) == 0);
	assert(astra_retained_observe(capture->registration) == 0);
}

static int32_t receive(void *data, int32_t value) {
	struct capture *capture = data;
	capture->calls++;
	if (value == 7) assert(counter_emit(capture->object, 8) == -2);
	if (value == 11) {
		assert(astra_retained_revoke(capture->registration) == 1);
		assert(astra_retained_observe(capture->registration) == 0);
		assert(astra_retained_retire(capture->registration) == 0);
	}
	return value * 2;
}

int main(void) {
	assert(astra_retained_install_provider(NULL) == -1);
	void *owner = counter_new(1);
	assert(!astra_gobject_signal_source(owner, (const uint8_t *)"missing", 7));
	assert(!astra_gobject_signal_source(owner, (const uint8_t *)"notify", 6));
	assert(!astra_gobject_signal_source(owner, (const uint8_t *)"changed\0x", 9));
	void *source = astra_gobject_signal_source(owner, (const uint8_t *)"changed", 7);
	assert(source);
	struct capture capture = {owner, NULL, 0};
	int32_t mode = astra_gobject_signal_mode(source);
	assert(!astra_retained_register(receive, &capture, 999999));
	assert(!astra_retained_register(receive, &capture, -1));
	capture.registration = astra_retained_register(receive, &capture, mode);
	assert(capture.registration && astra_gobject_signal_connections() == 1);
	assert(astra_retained_observe(capture.registration) == 0);
	assert(counter_emit(owner, 7) == 14 && capture.calls == 1);
	assert(counter_emit(owner, 9) == 18 && capture.calls == 2);
	assert(counter_emit(owner, 11) == 22 && capture.calls == 3);
	assert(astra_retained_observe(capture.registration) == 1);
	assert(counter_emit(owner, 12) == 0 && capture.calls == 3);
	assert(astra_retained_dispatch(capture.registration, 1) == -2);
	assert(astra_retained_revoke(capture.registration) == 1);
	assert(astra_retained_revoke(capture.registration) == 1);
	assert(astra_retained_retire(capture.registration) == 1);
	assert(astra_gobject_signal_connections() == 0);
	assert(astra_retained_dispatch(capture.registration, 1) == -3);
	assert(astra_retained_retire(capture.registration) == 0);
	astra_gobject_signal_source_free(source);
	assert(astra_gobject_signal_mode(source) == -1);
	assert(!astra_retained_register(receive, &capture, mode));
	astra_gobject_unref(owner);
	assert(counter_finalized() == 1);

	owner = counter_new(2);
	source = astra_gobject_signal_source(owner, (const uint8_t *)"changed", 7);
	mode = astra_gobject_signal_mode(source);
	astra_gobject_unref(owner);
	assert(counter_finalized() == 2);
	assert(!astra_retained_register(receive, &capture, mode));
	astra_gobject_signal_source_free(source);

	owner = counter_new(3);
	source = astra_gobject_signal_source(owner, (const uint8_t *)"changed", 7);
	capture.registration = astra_retained_register(receive, &capture, astra_gobject_signal_mode(source));
	assert(capture.registration);
	g_object_weak_ref(astra_gobject_peek(owner, ast_counter_get_type()), finalizing, &capture);
	astra_gobject_unref(owner);
	astra_gobject_signal_source_free(source);
	assert(counter_finalized() == 2);
	assert(astra_retained_revoke(capture.registration) == 1);
	assert(astra_retained_observe(capture.registration) == 1);
	assert(astra_retained_retire(capture.registration) == 1);
	assert(counter_finalized() == 3 && astra_gobject_signal_connections() == 0 && astra_gobject_live_handles() == 0);
	puts("GObject signal reentry/disconnect/quiescence/source-order guards PASS");
	return 0;
}
