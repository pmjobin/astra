/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "counter.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static int notifications, rejected_finalized;
static void notify(GObject *object, GParamSpec *spec, gpointer data) {
	(void)object;
	(void)spec;
	(void)data;
	notifications++;
}
static void finalized(gpointer data, GObject *object) {
	(void)data;
	(void)object;
	rejected_finalized++;
}

int main(void) {
	GObject *wrong = g_object_new(G_TYPE_OBJECT, NULL);
	g_object_weak_ref(wrong, finalized, NULL);
	assert(!astra_gobject_take(wrong, ast_counter_get_type()));
	assert(rejected_finalized == 1);
	assert(!astra_gobject_peek((void *)99999, G_TYPE_OBJECT));
	assert(!counter_new(10001));
	void *owner = counter_new(7);
	GObject *object = astra_gobject_peek(owner, ast_counter_get_type());
	assert(object && G_TYPE_FROM_INSTANCE(object) == ast_counter_get_type());
	assert(!astra_gobject_peek(owner, G_TYPE_INITIALLY_UNOWNED));
	gulong handler = g_signal_connect(object, "notify", G_CALLBACK(notify), NULL);
	assert(counter_set(owner, 42) == 1 && counter_get(owner) == 42 && notifications == 1);
	int32_t value;
	assert(astra_gobject_get_int(owner, "label", &value) == -1);
	assert(astra_gobject_set_int(owner, "missing", 1) == -1);
	assert(counter_set(owner, 10001) == -1 && counter_get(owner) == 42);
	assert(counter_label(owner, (const uint8_t *)"h\303\251llo", 6) == 1);
	void *text = counter_snapshot(owner);
	assert(text && astra_gobject_text_length(text) == 6);
	assert(astra_gobject_text_byte(text, 1) == 195 && astra_gobject_text_byte(text, 2) == 169);
	assert(astra_gobject_text_byte(text, -1) == -1 && astra_gobject_text_byte(text, 6) == -1);
	assert(counter_label(owner, (const uint8_t *)"a\0b", 3) == -1);
	assert(counter_label(owner, (const uint8_t *)"\377", 1) == -1);
	assert(counter_label(owner, NULL, 1) == -1 && counter_label(owner, NULL, -1) == -1);
	assert(counter_label(owner, (const uint8_t *)"changed", 7) == 1);
	assert(astra_gobject_text_length(text) == 6);
	astra_gobject_text_free(text);
	assert(astra_gobject_text_length(text) == -1);
	void *weak = astra_gobject_weak(owner), *second = astra_gobject_ref(owner);
	assert(weak && second && astra_gobject_same(owner, second) == 1);
	int32_t identity = astra_gobject_identity(owner);
	assert(identity > 0 && astra_gobject_identity(second) == identity);
	void *third = astra_gobject_upgrade(weak);
	assert(third && astra_gobject_same(second, third));
	astra_gobject_unref(second);
	astra_gobject_unref(third);
	assert(counter_finalized() == 0);
	g_signal_handler_disconnect(object, handler);
	g_object_run_dispose(object);
	assert(counter_disposed() == 1 && counter_get(owner) == INT32_MIN);
	assert(counter_set(owner, 1) == -1 && counter_emit(owner, 1) == -3);
	assert(astra_gobject_release_checked(owner) == 1);
	assert(astra_gobject_release_checked(owner) == -1 && counter_get(owner) == INT32_MIN);
	assert(!astra_gobject_upgrade(weak) && counter_finalized() == 1);
	astra_gobject_weak_free(weak);
	void *fresh = counter_new(9);
	assert(fresh != owner && astra_gobject_identity(fresh) != identity);
	assert(!astra_gobject_peek(owner, G_TYPE_OBJECT));
	astra_gobject_unref(fresh);

	void *full[256];
	for (size_t i = 0; i < G_N_ELEMENTS(full); i++) {
		full[i] = counter_new(0);
		assert(full[i]);
	}
	int32_t count = counter_finalized();
	assert(!counter_new(0) && counter_finalized() == count + 1);
	assert(!astra_gobject_ref(full[0]) && counter_get(full[0]) == 0);
	for (size_t i = 0; i < G_N_ELEMENTS(full); i++)
		astra_gobject_unref(full[i]);
	assert(astra_gobject_live_handles() == 0);
	puts("GObject identity/transfer/property/weak/capacity guards PASS");
	return 0;
}
