/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <glib-object.h>
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef struct Native Native;
typedef struct _OrbitTable16Directory Directory;
typedef struct _OrbitTable16Row Row;
typedef struct {
	float boost;
	double ceiling;
	int64_t minimum;
	uint64_t cap;
	uint32_t mask;
	bool lowest;
} Probe;
typedef struct {
	float score;
	int64_t code;
	uint32_t matches;
	bool found;
	uint64_t visited;
} Selection;
typedef struct {
	gfloat boost;
	gdouble ceiling;
	gint64 minimum;
	guint64 cap;
	guint mask;
	gboolean lowest;
} GProbe;
typedef struct {
	int32_t domain, code;
} Error;
extern int32_t orbit16_create(Native **, Error *);
extern int32_t orbit16_scan(Native *, Probe, Selection *, Error *);
extern uint32_t orbit16_acquire(Native *);
extern uint32_t orbit16_release(Native *);
extern Directory *orbit_table16_directory_as_gobject(Native *, GError **);
extern gboolean orbit_table16_directory_try_entry_for(Directory *, GProbe *, Row **, GError **);
extern uint32_t orbit16_retired_count(int32_t);
struct State {
	Native *root;
	unsigned complete, selected, destroyed;
	gulong connection;
	Row *saved;
	GBytes *description;
};
static void completed(Directory *object, gint requests, gboolean matched, gfloat score, gpointer data) {
	struct State *s = data;
	++s->complete;
	assert(requests == (gint)s->complete);
	if (requests == 1) {
		assert(matched && score == 0.5);
	}
	if (requests == 2) {
		assert(matched && score == 6.25);
	}
	if (requests == 3) {
		assert(!matched && score == 0);
	}
	g_object_ref(object);
	orbit16_acquire(s->root);
	orbit16_release(s->root);
	g_object_unref(object);
}
static void destroyed(gpointer data, GClosure *closure) {
	(void)closure;
	struct State *s = data;
	++s->destroyed;
}
static void selected(Directory *object, Row *item, GBytes *description, gpointer data) {
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
	assert(orbit16_create(&root, &native) == 0 && root);
	Directory *object = orbit_table16_directory_as_gobject(root, &error);
	assert(object && !error);
	gint requests = -1;
	gboolean enabled = FALSE;
	gdouble bias = 99;
	gchar *description = NULL;
	Row *last = NULL;
	g_object_get(object, "requests", &requests, "enabled", &enabled, "bias", &bias, "description", &description, "last", &last, NULL);
	assert(requests == 0 && enabled && bias == 0 && !strcmp(description, "Stream query λ") && !last);
	g_free(description);
	struct State state = {.root = root};
	g_signal_connect(object, "completed", G_CALLBACK(completed), &state);
	state.connection = g_signal_connect_data(object, "selected", G_CALLBACK(selected), &state, destroyed, 0);
	Probe query = {0, 10, 0, 0, 7, true};
	Selection answer = {0};
	assert(orbit16_scan(root, query, &answer, &native) == 0 && answer.code == 83 && answer.score == 0.5 && answer.matches == 3);
	assert(state.complete == 1 && state.selected == 1 && state.destroyed == 1);
	g_object_get(object, "last", &last, NULL);
	assert(last == state.saved);
	g_object_unref(last);
	GProbe requested = {0, 10, 30, 0, 7, FALSE};
	Row *found = NULL;
	assert(orbit_table16_directory_try_entry_for(object, &requested, &found, &error) && found && !error);
	gint64 code = 0;
	gdouble score = 0;
	g_object_get(found, "code", &code, "score", &score, NULL);
	assert(code == 47 && score == 6.25);
	g_object_get(object, "last", &last, NULL);
	assert(last && last != found);
	g_object_unref(last);
	g_object_set(object, "enabled", FALSE, NULL);
	Row *missing = NULL;
	assert(!orbit_table16_directory_try_entry_for(object, &requested, &missing, &error) && !missing && error && error->code == -1620);
	g_clear_error(&error);
	g_object_set(object, "enabled", TRUE, "bias", 1.0, NULL);
	requested.minimum = 0;
	requested.ceiling = 3;
	requested.mask = 3;
	requested.lowest = -23;
	assert(orbit_table16_directory_try_entry_for(object, &requested, &missing, &error) && !missing && !error);
	g_object_get(object, "last", &last, NULL);
	assert(!last && state.complete == 3 && state.selected == 1);
	orbit16_release(root);
	g_object_unref(object);
	assert(orbit16_retired_count(1) == 1 && orbit16_retired_count(2) == 1 && orbit16_retired_count(3) == 2 && orbit16_retired_count(4) == 1);
	g_object_get(state.saved, "code", &code, NULL);
	assert(code == 83);
	gsize length = 0;
	assert(!memcmp(g_bytes_get_data(state.description, &length), "Stream query λ", 15) && length == 15);
	g_object_unref(found);
	g_object_unref(state.saved);
	g_bytes_unref(state.description);
	assert(orbit16_retired_count(3) == 4);
	puts("PASS frozen API B3 GObject record inputs, nullable objects, metadata and retained signals");
	return 0;
}
