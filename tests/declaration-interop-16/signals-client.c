// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <glib-object.h>
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef struct Native Native;
typedef struct _Events16Session Session;

typedef struct {
	int32_t domain, code;
} Error;

extern int32_t signals16_create(int32_t, Native **, Error *);
extern int32_t signals16_update(Native *, int32_t, Error *);
extern int32_t signals16_choose_item(Native *, int32_t, Error *);
extern int32_t signals16_describe(Native *, const char *, int32_t, const uint8_t *, int32_t, Error *);
extern uint32_t signals16_release(Native *);
extern unsigned signals16_retired_count(void);
extern unsigned signals16_item_retired_count(void);
extern Session *events16_session_as_gobject(Native *, GError **);

typedef struct {
	Native *root;
	Session *object;
	gulong connection;
	unsigned calls, destroys;
	gboolean active;
} Observer;

typedef struct {
	gboolean valid;
	gdouble weight;
	gint64 revision;
} Sample;

static GBytes *retained_text, *retained_payload;
static Sample *retained_record;
static GType record_type;
static GObject *retained_item;

static void selected(Session *self, GObject *item, gpointer data) {
	Observer *o = data;
	assert(self == o->object && item);
	gint code = 0;
	g_object_get(item, "code", &code, NULL);
	assert(code == 37 && signals16_item_retired_count() == 0);
	retained_item = g_object_ref(item);
}

static void described(Session *self, GBytes *text, GBytes *payload, const Sample *record, gpointer data) {
	Observer *o = data;
	assert(self == o->object && record->valid == TRUE && record->weight == 3.5 && record->revision == 29);
	gsize length = 0;
	const char *bytes = g_bytes_get_data(text, &length);
	assert(length == 3 && memcmp(bytes, "a\0b", 3) == 0);
	bytes = g_bytes_get_data(payload, &length);
	assert(length == 3 && memcmp(bytes, "\3\0\376", 3) == 0);
	retained_text = g_bytes_ref(text);
	retained_payload = g_bytes_ref(payload);
	retained_record = g_boxed_copy(record_type, record);
}

static void destroy(gpointer data, GClosure *closure) {
	Observer *o = data;
	(void)closure;
	assert(!o->active);
	++o->destroys;
}

static void updated(Session *self, gint count, gboolean committed, gdouble weight, gpointer data) {
	Observer *o = data;
	assert(self == o->object && count == 19 && committed && weight == 2.5);
	o->active = TRUE;
	++o->calls;
	gint observed = 0;
	g_object_get(self, "count", &observed, NULL);
	assert(observed == count);
	g_signal_handler_disconnect(self, o->connection);
	assert(o->destroys == 0);
	signals16_release(o->root);
	o->root = NULL;
	g_object_unref(o->object);
	o->object = NULL;
	assert(signals16_retired_count() == 0);
	o->active = FALSE;
}

int main(void) {
	Error native = {0, 0};
	GError *error = NULL;
	Observer o = {0};
	assert(signals16_create(7, &o.root, &native) == 0 && o.root);
	o.object = events16_session_as_gobject(o.root, &error);
	assert(o.object && !error);
	GSignalQuery query;
	g_signal_query(g_signal_lookup("described", G_OBJECT_TYPE(o.object)), &query);
	assert(query.return_type == G_TYPE_NONE && query.n_params == 3 && query.param_types[0] == G_TYPE_BYTES && query.param_types[1] == G_TYPE_BYTES);
	record_type = query.param_types[2];
	assert(g_type_is_a(record_type, G_TYPE_BOXED));
	g_signal_connect(o.object, "described", G_CALLBACK(described), &o);
	const uint8_t payload[] = {3, 0, 254};
	assert(signals16_describe(o.root, "a\0b", 3, payload, 3, &native) == 0 && retained_text && retained_payload && retained_record);
	g_signal_connect(o.object, "selected", G_CALLBACK(selected), &o);
	assert(signals16_choose_item(o.root, 37, &native) == 0 && retained_item && signals16_item_retired_count() == 0);
	o.connection = g_signal_connect_data(o.object, "updated", G_CALLBACK(updated), &o, destroy, 0);
	assert(o.connection && signals16_update(o.root, 19, &native) == 0);
	assert(o.calls == 1 && o.destroys == 1 && !o.root && !o.object && signals16_retired_count() == 1);
	gsize length = 0;
	const char *bytes = g_bytes_get_data(retained_text, &length);
	assert(length == 3 && memcmp(bytes, "a\0b", 3) == 0);
	assert(retained_record->valid && retained_record->revision == 29);
	g_bytes_unref(retained_text);
	g_bytes_unref(retained_payload);
	g_boxed_free(record_type, retained_record);
	gint code = 0;
	g_object_get(retained_item, "code", &code, NULL);
	assert(code == 37);
	g_object_unref(retained_item);
	assert(signals16_item_retired_count() == 1);
	puts("PASS native typed signal delivery, committed state, self-disconnect and pinned final-owner release");
	return 0;
}
