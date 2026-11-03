/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "gobject-signals-16.h"
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
typedef void (*Callback)(void *, int32_t, bool, double);

typedef struct {
	GObject *object;
	void *token;
	guint signal;
	unsigned calls;
	gboolean active;
} Context;

static unsigned retired;

static void finalized(gpointer data, GObject *object) {
	(void)data;
	(void)object;
	++retired;
}

static void receive(void *data, int32_t value, bool committed, double weight) {
	Context *c = data;
	assert(value == 37 && committed && weight == 2.5 && !c->active);
	c->active = TRUE;
	++c->calls;
	g_signal_emit(c->object, c->signal, 0, 99, FALSE, 9.0);
	assert(c->calls == 1 && astra_gobject16_signal_reentry_refusals() == 1);
	assert(astra_gobject16_signal_revoke(c->token) == 1 && astra_gobject16_signal_observe(c->token) == 0);
	assert(astra_gobject16_signal_retire(c->token) == 0 && retired == 0);
	c->active = FALSE;
}

static void marshal(GClosure *closure, GValue *result, guint count, const GValue *values, gpointer hint, gpointer extra) {
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
	callback(astra_gobject16_signal_context(connection), g_value_get_int(&values[1]), g_value_get_boolean(&values[2]) != FALSE, g_value_get_double(&values[3]));
	astra_gobject16_signal_leave(connection);
}

typedef struct {
	void *source, *token;
} Worker;

static gpointer wrong_thread(gpointer data) {
	Worker *w = data;
	assert(astra_gobject16_signal_mode(w->source) == -1 && astra_gobject16_signal_revoke(w->token) == -3 && astra_gobject16_signal_observe(w->token) == -3);
	return NULL;
}

int main(void) {
	Context c = {0};
	c.object = g_object_new(G_TYPE_OBJECT, NULL);
	g_object_weak_ref(c.object, finalized, NULL);
	c.signal = g_signal_new("declaration-event", G_TYPE_OBJECT, G_SIGNAL_RUN_LAST, 0, NULL, NULL, NULL, G_TYPE_NONE, 3, G_TYPE_INT, G_TYPE_BOOLEAN, G_TYPE_DOUBLE);
	const GType types[] = {G_TYPE_INT, G_TYPE_BOOLEAN, G_TYPE_DOUBLE}, wrong[] = {G_TYPE_BOOLEAN, G_TYPE_INT, G_TYPE_DOUBLE};
	assert(!astra_gobject16_signal_source(c.object, "declaration-event", "void;i32,bool,f64", marshal, 3, wrong));
	void *source = astra_gobject16_signal_source(c.object, "declaration-event", "void;i32,bool,f64", marshal, 3, types);
	assert(source);
	int32_t mode = astra_gobject16_signal_mode(source);
	assert(mode > 0 && !astra_gobject16_signal_register((void (*)(void))receive, &c, mode, "void;i64,bool,f64"));
	c.token = astra_gobject16_signal_register((void (*)(void))receive, &c, mode, "void;i32,bool,f64");
	assert(c.token && astra_gobject16_signal_connections() == 1);
	Worker w = {source, c.token};
	GThread *thread = g_thread_new("signal-context", wrong_thread, &w);
	g_thread_join(thread);
	astra_gobject16_signal_source_free(source);
	assert(!astra_gobject16_signal_register((void (*)(void))receive, &c, mode, "void;i32,bool,f64"));
	g_object_unref(c.object);
	assert(retired == 0);
	g_signal_emit(c.object, c.signal, 0, 37, TRUE, 2.5);
	assert(c.calls == 1 && !c.active && astra_gobject16_signal_observe(c.token) == 1 && retired == 0);
	assert(astra_gobject16_signal_retire(c.token) == 1 && retired == 1 && astra_gobject16_signal_connections() == 0);
	assert(astra_gobject16_signal_retire(c.token) == 0 && astra_gobject16_signal_revoke(c.token) == -3);
	puts("PASS typed retained signal exact signature, context, recursive refusal, self-disconnect, foreign retirement and stale-token cleanup");
	return 0;
}
