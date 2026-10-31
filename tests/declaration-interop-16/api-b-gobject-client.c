/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <glib-object.h>
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef struct Native Native;
typedef struct _RecordQuery16Index Index;
typedef struct _RecordQuery16Match Match;
typedef struct {
	int64_t minimum;
	double ceiling;
	uint32_t mask;
	bool lowest;
} Query;
typedef struct {
	int64_t code;
	double score;
	uint32_t matches;
	bool found;
} Answer;
typedef struct {
	gint64 minimum;
	gdouble ceiling;
	guint mask;
	gboolean lowest;
} GQuery;
typedef struct {
	int32_t domain, code;
} Error;
extern int32_t record_query16_create(Native **, Error *);
extern int32_t record_query16_search(Native *, Query, Answer *, Error *);
extern uint32_t record_query16_acquire(Native *);
extern uint32_t record_query16_release(Native *);
extern Index *record_query16_index_as_gobject(Native *, GError **);
extern gboolean record_query16_index_try_find(Index *, GQuery *, Match **, GError **);
extern uint32_t query16_retired_count(int32_t);
struct State {
	Native *root;
	unsigned complete, selected, destroyed;
	gulong connection;
	Match *saved;
	GBytes *description;
};
static void completed(Index *object, gint requests, gboolean matched, gdouble score, gpointer data) {
	struct State *s = data;
	++s->complete;
	assert(requests == (gint)s->complete);
	if (requests == 1) {
		assert(matched && score == 1.75);
	}
	if (requests == 2) {
		assert(matched && score == 5.5);
	}
	if (requests == 3) {
		assert(!matched && score == 0);
	}
	g_object_ref(object);
	record_query16_acquire(s->root);
	record_query16_release(s->root);
	g_object_unref(object);
}
static void destroyed(gpointer data, GClosure *closure) {
	(void)closure;
	struct State *s = data;
	++s->destroyed;
}
static void selected(Index *object, Match *item, GBytes *description, gpointer data) {
	struct State *s = data;
	assert(s->complete == 1 && item && description);
	++s->selected;
	s->saved = g_object_ref(item);
	s->description = g_bytes_ref(description);
	g_signal_handler_disconnect(object, s->connection);
	assert(s->destroyed == 0);
}
int main(void) {
	Native *root = NULL;
	Error native = {0};
	GError *error = NULL;
	assert(record_query16_create(&root, &native) == 0 && root);
	Index *object = record_query16_index_as_gobject(root, &error);
	assert(object && !error);
	gint requests = -1;
	gboolean enabled = FALSE;
	gdouble bias = 99;
	gchar *description = NULL;
	Match *last = NULL;
	g_object_get(object, "requests", &requests, "enabled", &enabled, "bias", &bias, "description", &description, "last", &last, NULL);
	assert(requests == 0 && enabled && bias == 0 && !strcmp(description, "Record index λ") && !last);
	g_free(description);
	struct State state = {.root = root};
	g_signal_connect(object, "completed", G_CALLBACK(completed), &state);
	state.connection = g_signal_connect_data(object, "selected", G_CALLBACK(selected), &state, destroyed, 0);
	Query query = {0, 10, 7, true};
	Answer answer = {0};
	assert(record_query16_search(root, query, &answer, &native) == 0 && answer.code == 59 && answer.score == 1.75 && answer.matches == 3);
	assert(state.complete == 1 && state.selected == 1 && state.destroyed == 1);
	g_object_get(object, "last", &last, NULL);
	assert(last == state.saved);
	g_object_unref(last);
	GQuery requested = {20, 10, 7, FALSE};
	Match *found = NULL;
	assert(record_query16_index_try_find(object, &requested, &found, &error) && found && !error);
	gint64 code = 0;
	gdouble score = 0;
	g_object_get(found, "code", &code, "score", &score, NULL);
	assert(code == 31 && score == 5.5);
	g_object_get(object, "last", &last, NULL);
	assert(last && last != found);
	g_object_unref(last);
	g_object_set(object, "enabled", FALSE, NULL);
	Match *missing = NULL;
	assert(!record_query16_index_try_find(object, &requested, &missing, &error) && !missing && error && error->code == -1620);
	g_clear_error(&error);
	g_object_set(object, "enabled", TRUE, "bias", 1.0, NULL);
	requested.minimum = 0;
	requested.ceiling = 3;
	requested.mask = 3;
	requested.lowest = -17;
	assert(record_query16_index_try_find(object, &requested, &missing, &error) && !missing && !error);
	g_object_get(object, "last", &last, NULL);
	assert(!last && state.complete == 3 && state.selected == 1);
	record_query16_release(root);
	g_object_unref(object);
	assert(query16_retired_count(1) == 1 && query16_retired_count(2) == 1 && query16_retired_count(3) == 2 && query16_retired_count(4) == 1);
	g_object_get(state.saved, "code", &code, NULL);
	assert(code == 59);
	gsize length = 0;
	assert(!memcmp(g_bytes_get_data(state.description, &length), "Record index λ", 15) && length == 15);
	g_object_unref(found);
	g_object_unref(state.saved);
	g_bytes_unref(state.description);
	assert(query16_retired_count(3) == 4);
	puts("PASS frozen API B GObject record inputs, nullable objects, metadata and retained signals");
	return 0;
}
