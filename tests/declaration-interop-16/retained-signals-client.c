/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "gobject-signals-16.h"
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
typedef void (*Callback)(void *, int32_t, bool, double);
extern int32_t retained16_run(int32_t);
static GObject *provider;
static guint event_signal;
static unsigned notes;
static int32_t values[8];

int32_t retained16_note(int32_t value) {
	assert(notes < 8);
	values[notes++] = value;
	return 0;
}

int32_t retained16_fire(void) {
	g_signal_emit(provider, event_signal, 0, 37, TRUE, 2.5);
	return 0;
}

int32_t retained16_recursive(void) {
	g_signal_emit(provider, event_signal, 0, 99, FALSE, 9.0);
	return 0;
}

int32_t retained16_stop(void) {
	g_signal_handlers_destroy(provider);
	assert(astra_gobject16_signal_connections() == 1);
	return 0;
}

static void marshal(GClosure *closure, GValue *result, guint count, const GValue *arguments, gpointer hint, gpointer extra) {
	(void)result;
	(void)hint;
	(void)extra;
	assert(count == 4);
	void *connection = closure->data;
	if (astra_gobject16_signal_enter(connection) != 1) {
		return;
	}
	Callback callback = (Callback)astra_gobject16_signal_callback(connection);
	assert(callback);
	callback(astra_gobject16_signal_context(connection), g_value_get_int(&arguments[1]), g_value_get_boolean(&arguments[2]) != FALSE, g_value_get_double(&arguments[3]));
	astra_gobject16_signal_leave(connection);
}

int main(void) {
	provider = g_object_new(G_TYPE_OBJECT, NULL);
	event_signal = g_signal_new("typed-native", G_TYPE_OBJECT, G_SIGNAL_RUN_LAST, 0, NULL, NULL, NULL, G_TYPE_NONE, 3, G_TYPE_INT, G_TYPE_BOOLEAN, G_TYPE_DOUBLE);
	const GType types[] = {G_TYPE_INT, G_TYPE_BOOLEAN, G_TYPE_DOUBLE};
	/* Independent normalized scalar signature, using the public descriptor format. */
	const char *signature = "14:0::0:3:1:0::0:0:-;7:0::0:0:-;6:0::0:0:-;0:0::0:0:-;";
	void *source = astra_gobject16_signal_source(provider, "typed-native", signature, marshal, 3, types);
	assert(source);
	assert(retained16_run(astra_gobject16_signal_mode(source)) == 0 && notes == 2 && values[0] == 1 && values[1] == 101);
	assert(astra_gobject16_signal_connections() == 0 && astra_gobject16_signal_reentry_refusals() == 1);
	astra_gobject16_signal_source_free(source);
	g_object_unref(provider);
	puts("PASS native void Closure retained by exact typed GObject registration, recursive refusal and observed foreign retirement before environment destruction");
	return 0;
}
