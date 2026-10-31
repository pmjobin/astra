// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <glib-object.h>
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef struct Native Native;
typedef struct _Opaque16Session Session;
typedef struct {
	int32_t domain, code;
} Error;
extern int32_t gobjectunit16_create(int32_t, double, Native **, Error *);
extern int32_t gobjectunit16_get_count(Native *, int32_t *, Error *);
extern uint32_t gobjectunit16_release(Native *);
extern unsigned gobjectunit16_retired_count(void);
extern Session *opaque16_session_as_gobject(Native *, GError **);
extern gboolean opaque16_session_try_evaluate(Session *, gdouble, gdouble *, GError **);
extern gboolean opaque16_session_try_snapshot(Session *, GBytes *, GBytes **, GError **);
extern gboolean opaque16_session_try_visit(Session *, gboolean, gboolean (*)(gpointer, gboolean), gpointer, gboolean *, GError **);
static unsigned callbacks;
static gboolean invert(gpointer data, gboolean input) {
	assert(data == &callbacks);
	++callbacks;
	return !input;
}
int main(void) {
	Native *root = NULL;
	Error native = {0, 0};
	GError *error = NULL;
	assert(gobjectunit16_create(7, 1.5, &root, &native) == 0 && root);
	Session *object = opaque16_session_as_gobject(root, &error), *again = opaque16_session_as_gobject(root, &error);
	assert(object && again == object && !error);
	g_object_set(object, "count", 19, NULL);
	int32_t count = 0;
	assert(gobjectunit16_get_count(root, &count, &native) == 0 && count == 19);
	gdouble value = 99;
	assert(opaque16_session_try_evaluate(object, 4, &value, &error) && value == 25);
	assert(!opaque16_session_try_evaluate(object, -1, &value, &error) && value == 0 && error && error->code == -1600);
	g_clear_error(&error);
	const guint8 input[] = {3, 0, 254};
	GBytes *bytes = g_bytes_new_static(input, 3), *copy = NULL;
	assert(opaque16_session_try_snapshot(object, bytes, &copy, &error) && copy);
	gsize length = 0;
	const guint8 *result = g_bytes_get_data(copy, &length);
	assert(length == 3 && result[0] == 86 && result[1] == 85 && result[2] == 171);
	g_bytes_unref(copy);
	g_bytes_unref(bytes);
	gboolean chosen = FALSE;
	assert(opaque16_session_try_visit(object, FALSE, invert, &callbacks, &chosen, &error) && chosen && callbacks == 1);
	gobjectunit16_release(root);
	g_object_unref(again);
	assert(gobjectunit16_retired_count() == 0);
	g_object_unref(object);
	assert(gobjectunit16_retired_count() == 1);
	puts("PASS opaque shared C and GObject views execute native algorithms and retire once");
	return 0;
}
