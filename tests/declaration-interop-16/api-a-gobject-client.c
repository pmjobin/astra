/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <glib-object.h>
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef struct Native Native;
typedef struct _ByteService16Session Session;
typedef struct _ByteService16Token Token;

typedef struct {
	int32_t mask;
	bool rotate;
	double weight;
} Configuration;

typedef struct {
	double score;
	uint64_t revision, processed;
} Statistics;

typedef struct {
	int32_t domain, code;
} Error;

extern int32_t byte_service16_create(Configuration, Native **, Error *);
extern int32_t byte_service16_statistics(Native *, Statistics *, Error *);
extern uint32_t byte_service16_acquire(Native *);
extern uint32_t byte_service16_release(Native *);
extern Session *byte_service16_session_as_gobject(Native *, GError **);
extern gboolean byte_service16_session_try_process(Session *, GBytes *, guint8 **, gint *, gint *, GError **);
extern gboolean byte_service16_session_try_snapshot(Session *, GBytes **, GError **);
extern uint32_t byte16_retired_count(int32_t);

struct State {
	Native *root;
	gulong handler;
	unsigned processed, payload, destroyed;
	Token *token;
	GBytes *label;
};

static void processed(Session *object, gint revision, gboolean committed, gdouble weight, gpointer data) {
	struct State *s = data;
	assert(revision == 1 && committed && weight == 2.5);
	++s->processed;
	Statistics statistics = {0};
	Error error = {0};
	assert(byte_service16_statistics(s->root, &statistics, &error) == 0 && statistics.revision == 1 && statistics.score == 1072.5);
	g_object_ref(object);
	byte_service16_acquire(s->root);
	byte_service16_release(s->root);
	g_object_unref(object);
}

static void destroyed(gpointer data, GClosure *closure) {
	(void)closure;
	struct State *s = data;
	++s->destroyed;
}

static void payload(Session *object, Token *token, GBytes *label, gpointer data) {
	struct State *s = data;
	assert(token && label && s->processed == 1);
	++s->payload;
	s->token = g_object_ref(token);
	s->label = g_bytes_ref(label);
	g_signal_handler_disconnect(object, s->handler);
	assert(s->destroyed == 0);
}

int main(void) {
	Native *root = NULL;
	Error native = {0};
	Configuration configuration = {85, true, 2.5};
	assert(byte_service16_create(configuration, &root, &native) == 0);
	GError *error = NULL;
	Session *object = byte_service16_session_as_gobject(root, &error);
	assert(object && !error);
	gint revision = -1;
	gboolean enabled = FALSE;
	gdouble weight = 0;
	gchar *label = NULL;
	Token *current = NULL;
	g_object_get(object, "revision", &revision, "enabled", &enabled, "weight", &weight, "label", &label, "current", &current, NULL);
	assert(revision == 0 && enabled && weight == 2.5 && !strcmp(label, "Byte transform é") && !current);
	g_free(label);
	struct State state = {.root = root};
	g_signal_connect(object, "processed", G_CALLBACK(processed), &state);
	state.handler = g_signal_connect_data(object, "snapshot-ready", G_CALLBACK(payload), &state, destroyed, 0);
	const guint8 input[] = {3, 0, 254};
	GBytes *bytes = g_bytes_new_static(input, 3);
	guint8 storage[] = {77, 77, 77, 77}, *output = storage;
	gint capacity = 4, produced = -1;
	assert(byte_service16_session_try_process(object, bytes, &output, &capacity, &produced, &error) && !error && output == storage && capacity == 4 && produced == 3 && storage[0] == 172 && storage[1] == 170 && storage[2] == 87 && storage[3] == 77);
	assert(state.processed == 1 && state.payload == 1 && state.destroyed == 1);
	g_object_get(object, "current", &current, NULL);
	assert(current == state.token);
	g_object_unref(current);
	GBytes *snapshot = NULL;
	assert(byte_service16_session_try_snapshot(object, &snapshot, &error) && snapshot);
	gsize count = 0;
	const guint8 *saved = g_bytes_get_data(snapshot, &count);
	assert(count == 3 && !memcmp(saved, storage, 3));
	g_object_set(object, "enabled", FALSE, NULL);
	assert(!byte_service16_session_try_process(object, bytes, &output, &capacity, &produced, &error) && error && error->code == -1610 && produced == 0);
	g_clear_error(&error);
	g_object_set(object, "enabled", TRUE, NULL);
	capacity = 2;
	storage[0] = 77;
	assert(!byte_service16_session_try_process(object, bytes, &output, &capacity, &produced, &error) && error && error->code == -1610 && produced == 0 && storage[0] == 77);
	g_clear_error(&error);
	assert(state.processed == 1 && state.payload == 1);
	byte_service16_release(root);
	g_object_unref(object);
	assert(byte16_retired_count(1) == 1 && byte16_retired_count(3) == 1 && byte16_retired_count(4) == 0);
	g_object_get(state.token, "revision", &revision, NULL);
	assert(revision == 1);
	const char *text = g_bytes_get_data(state.label, &count);
	assert(count == 17 && !memcmp(text, "Byte transform é", 17));
	assert(!memcmp(saved, "\254\252\127", 3));
	g_object_unref(state.token);
	assert(byte16_retired_count(4) == 1);
	g_bytes_unref(state.label);
	g_bytes_unref(snapshot);
	g_bytes_unref(bytes);
	puts("PASS API A GObject properties, typed signals, quiescent disconnect and retained native object/text values");
	return 0;
}
