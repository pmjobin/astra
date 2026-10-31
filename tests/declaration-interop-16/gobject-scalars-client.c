// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <glib-object.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stddef.h>
typedef struct _Astra16Session Astra16Session;
typedef struct go16_native_handle NativeHandle;
typedef struct {
	int32_t domain, code;
} NativeError;
// Independent GLib and C declarations; the emitted SDK does not define this oracle.
extern GType astra16_session_get_type(void);
extern Astra16Session *astra16_session_new(gint, gboolean, gdouble, GError **);
extern Astra16Session *astra16_session_as_gobject(NativeHandle *, GError **);
extern gboolean astra16_session_try_get_count(Astra16Session *, gint *, GError **);
extern gboolean astra16_session_try_fold(Astra16Session *, gint64, guint, gfloat, guint64, gint64 *, GError **);
extern gboolean astra16_session_try_choose(Astra16Session *, gboolean, gboolean *, GError **);
extern gboolean astra16_session_try_evaluate(Astra16Session *, gdouble, gdouble *, GError **);
extern int32_t go16_native_create(int32_t, bool, double, NativeHandle **, NativeError *);
extern int32_t go16_native_get_count(NativeHandle *, int32_t *, NativeError *);
extern int32_t go16_native_native_only(NativeHandle *, int32_t, int32_t *, NativeError *);
extern uint32_t go16_native_release(NativeHandle *);
extern int32_t go16_destroyed_count(void);

typedef gboolean (*FlagCallback)(gpointer, gboolean);
typedef void (*SinkCallback)(gpointer, gdouble);
extern gboolean astra16_session_try_visit(Astra16Session *, gboolean, FlagCallback, gpointer, gboolean *, GError **);
extern gboolean astra16_session_try_maybe_visit(Astra16Session *, gboolean, FlagCallback, gpointer, gboolean *, GError **);
extern gboolean astra16_session_try_deliver(Astra16Session *, gdouble, SinkCallback, gpointer, GError **);
extern gboolean astra16_session_try_eval_refs(Astra16Session *, gint64, gdouble *, guint *, gboolean, gint64 *, GError **);
static guint callback_calls;
static gboolean flag_callback(gpointer data, gboolean input) {
	assert(data == &callback_calls && input == TRUE);
	++callback_calls;
	return 7;
}
static void sink_callback(gpointer data, gdouble input) {
	assert(data == &callback_calls && input == 1.25);
	++callback_calls;
}
static void callbacks_and_refs(Astra16Session *object) {
	GError *error = NULL;
	gboolean result = FALSE;
	assert(astra16_session_try_visit(object, 7, flag_callback, &callback_calls, &result, &error) && result == TRUE && callback_calls == 1);
	assert(astra16_session_try_maybe_visit(object, 7, NULL, NULL, &result, &error) && result == TRUE && callback_calls == 1);
	assert(astra16_session_try_deliver(object, 1.25, sink_callback, &callback_calls, &error) && callback_calls == 2);
	gint64 input = INT64_C(-5000000000), value = 99;
	gdouble scale = 2.5;
	guint count = 99;
	assert(astra16_session_try_eval_refs(object, input, &scale, &count, FALSE, &value, &error) && input == INT64_C(-5000000000) && scale == 4.0 && count == UINT32_C(4000000000) && value == INT64_C(-4999999995));
	scale = 2.5;
	count = 99;
	value = 99;
	assert(!astra16_session_try_eval_refs(object, input, &scale, &count, TRUE, &value, &error) && input == INT64_C(-5000000000) && scale == 2.5 && count == 0 && value == 0 && error && error->code == -1600);
	g_clear_error(&error);
	assert(!astra16_session_try_visit(object, TRUE, NULL, NULL, &result, &error) && !result && error);
	g_clear_error(&error);
}

extern gboolean astra16_session_try_digest(Astra16Session *, GBytes *, gint *, GError **);
extern gboolean astra16_session_try_snapshot(Astra16Session *, GBytes *, GBytes **, GError **);
extern gboolean astra16_session_try_transform(Astra16Session *, GBytes *, guint8 **, gint *, gint *, GError **);
extern gboolean astra16_session_try_measure(Astra16Session *, GBytes *, gint *, GError **);
extern gboolean astra16_session_try_counted_text(Astra16Session *, GBytes **, GError **);
extern gboolean astra16_session_try_terminated_length(Astra16Session *, gchar *, gint *, GError **);
extern gboolean astra16_session_try_terminated(Astra16Session *, gchar **, GError **);
extern gboolean astra16_session_try_forbidden_nul(Astra16Session *, gchar **, GError **);
static void payloads(Astra16Session *object) {
	GError *error = NULL;
	const guint8 data[] = {1, 0, 254};
	GBytes *input = g_bytes_new_static(data, 3), *owned = NULL;
	gint value = 0;
	assert(astra16_session_try_digest(object, input, &value, &error) && value == 255);
	assert(astra16_session_try_snapshot(object, input, &owned, &error));
	gsize length = 0;
	const guint8 *copy = g_bytes_get_data(owned, &length);
	assert(length == 3 && copy[0] == 84 && copy[1] == 85 && copy[2] == 171);
	g_bytes_unref(owned);
	guint8 output[] = {9, 9, 9, 9};
	guint8 *slot = output;
	gint capacity = 4;
	assert(astra16_session_try_transform(object, input, &slot, &capacity, &value, &error) && value == 3 && output[0] == 2 && output[1] == 1 && output[2] == 255 && output[3] == 9);
	output[0] = 9;
	capacity = 1;
	assert(!astra16_session_try_transform(object, input, &slot, &capacity, &value, &error) && output[0] == 9 && value == 0 && error);
	g_clear_error(&error);
	g_bytes_unref(input);
	input = g_bytes_new_static("hé\0llo", 7);
	assert(astra16_session_try_measure(object, input, &value, &error) && value == 7);
	assert(astra16_session_try_counted_text(object, &owned, &error));
	copy = g_bytes_get_data(owned, &length);
	assert(length == 7 && !memcmp(copy, "hé\0llo", 7));
	g_bytes_unref(input);
	g_bytes_unref(owned);
	gchar *text = NULL;
	assert(astra16_session_try_terminated(object, &text, &error) && !strcmp(text, "café"));
	g_free(text);
	assert(astra16_session_try_terminated_length(object, "café", &value, &error) && value == 5);
	assert(!astra16_session_try_forbidden_nul(object, &text, &error) && !text && error);
	g_clear_error(&error);
	input = g_bytes_new(NULL, 0);
	assert(astra16_session_try_digest(object, input, &value, &error) && value == 0);
	g_bytes_unref(input);
}

typedef struct {
	gint count;
	gdouble scale;
	gboolean enabled;
	guint mask;
	guint64 stamp;
	gfloat weight;
} IndependentSample;
_Static_assert(sizeof(IndependentSample) == 40 && _Alignof(IndependentSample) == 8 && offsetof(IndependentSample, enabled) == 16 && offsetof(IndependentSample, mask) == 20 && offsetof(IndependentSample, stamp) == 24 && offsetof(IndependentSample, weight) == 32, "independent GLib BOOL32 POD oracle");
extern gboolean astra16_session_try_adjust(Astra16Session *, IndependentSample *, IndependentSample **, GError **);
static void records(Astra16Session *object) {
	IndependentSample input = {2, 3.5, 7, 4000000000u, UINT64_C(9000000001), 1.25f}, *result = NULL;
	GError *error = NULL;
	assert(astra16_session_try_adjust(object, &input, &result, &error) && result && result->count == 21 && result->scale == 8.75 && result->enabled == FALSE && result->mask == 4000000000u && result->stamp == UINT64_C(9000000002) && result->weight == 1.75f);
	assert(input.enabled == 7 && input.count == 2);
	g_free(result);
	assert(!astra16_session_try_adjust(object, NULL, &result, &error) && !result && error);
	g_clear_error(&error);
}

typedef struct _Astra16Item Astra16Item;
extern GType astra16_item_get_type(void);
extern Astra16Item *astra16_item_new(gint, GError **);
extern gboolean astra16_session_try_spawn(Astra16Session *, gint, Astra16Item **, GError **);
extern gboolean astra16_session_try_inspect(Astra16Session *, Astra16Item *, gint *, GError **);
extern gboolean astra16_session_try_duplicate(Astra16Session *, Astra16Item *, Astra16Item **, GError **);
extern gboolean astra16_session_try_relay(Astra16Session *, Astra16Item *, Astra16Item **, GError **);
extern gboolean astra16_session_try_lookup(Astra16Session *, gboolean, Astra16Item *, Astra16Item **, GError **);
extern gboolean astra16_session_try_optional(Astra16Session *, Astra16Item *, gint *, GError **);
extern gboolean astra16_session_try_watched(Astra16Session *, Astra16Item *, void (*)(gpointer), gpointer, gint *, GError **);
extern int32_t go16_item_destroyed_count(void);
static void release_argument(gpointer value) {
	g_object_unref(value);
	assert(go16_item_destroyed_count() == 0);
}
extern gboolean astra16_session_try_read_current(Astra16Session *, gint *, GError **);
static void objects(Astra16Session *object) {
	GError *error = NULL;
	gint current_value = 0;
	assert(astra16_session_try_read_current(object, &current_value, &error) && current_value == 41);
	Astra16Item *child = NULL;
	GBytes *title = NULL;
	g_object_get(object, "current", &child, "title", &title, NULL);
	assert(child && title);
	gsize title_length = 0;
	const char *title_data = g_bytes_get_data(title, &title_length);
	assert(title_length == 7 && !memcmp(title_data, "hé\0llo", 7));
	g_bytes_unref(title);
	g_object_unref(child);
	Astra16Item *item = NULL, *copy = NULL;
	gint value = 0;
	assert(astra16_session_try_spawn(object, 5, &item, &error) && item);
	assert(astra16_session_try_inspect(object, item, &value, &error) && value == 24);
	assert(astra16_session_try_duplicate(object, item, &copy, &error) && copy == item);
	g_object_unref(copy);
	assert(astra16_session_try_lookup(object, FALSE, item, &copy, &error) && !copy);
	assert(astra16_session_try_optional(object, NULL, &value, &error) && value == -7);
	assert(astra16_session_try_relay(object, g_object_ref(item), &copy, &error) && copy == item);
	g_object_unref(copy);
	GObject *wrong = g_object_new(G_TYPE_OBJECT, NULL);
	assert(!astra16_session_try_inspect(object, (Astra16Item *)wrong, &value, &error) && value == 0 && error);
	g_clear_error(&error);
	g_object_unref(wrong);
	assert(astra16_session_try_watched(object, item, release_argument, item, &value, &error) && value == 24 && go16_item_destroyed_count() == 1);
	item = astra16_item_new(9, &error);
	assert(item);
	g_object_run_dispose(G_OBJECT(item));
	assert(!astra16_session_try_inspect(object, item, &value, &error) && value == 0 && error);
	g_clear_error(&error);
	g_object_unref(item);
	assert(go16_item_destroyed_count() == 2);
}
static unsigned notices;
static void notified(GObject *object, GParamSpec *spec, gpointer data) {
	assert(object && spec && data == &notices);
	++notices;
}
struct ThreadProbe {
	Astra16Session *object;
};
static gpointer wrong_thread(gpointer opaque) {
	struct ThreadProbe *probe = opaque;
	GError *error = NULL;
	gint value = 99;
	assert(!astra16_session_try_get_count(probe->object, &value, &error) && value == 0 && error && error->code == (int32_t)UINT32_C(0x8001010e));
	g_error_free(error);
	return NULL;
}
int main(void) {
	GError *error = NULL;
	Astra16Session *object = astra16_session_new(7, 7, 1.5, &error);
	assert(object && !error && !g_object_is_floating(object) && G_TYPE_IS_FINAL(astra16_session_get_type()) && G_TYPE_IS_FINAL(astra16_item_get_type()));
	guint count = 0;
	GParamSpec **properties = g_object_class_list_properties(G_OBJECT_GET_CLASS(object), &count);
	assert(count == 5);
	g_free(properties);
	assert(G_PARAM_SPEC_VALUE_TYPE(g_object_class_find_property(G_OBJECT_GET_CLASS(object), "count")) == G_TYPE_INT);
	assert(G_PARAM_SPEC_VALUE_TYPE(g_object_class_find_property(G_OBJECT_GET_CLASS(object), "enabled")) == G_TYPE_BOOLEAN);
	assert(G_PARAM_SPEC_VALUE_TYPE(g_object_class_find_property(G_OBJECT_GET_CLASS(object), "scale")) == G_TYPE_DOUBLE);
	g_signal_connect(object, "notify", G_CALLBACK(notified), &notices);
	gint value = 0;
	gboolean enabled = FALSE;
	gdouble scale = 0;
	g_object_get(object, "count", &value, "enabled", &enabled, "scale", &scale, NULL);
	assert(value == 7 && enabled && scale == 1.5);
	g_object_set(object, "count", 19, "enabled", FALSE, "scale", 2.5, NULL);
	assert(notices == 3);
	gint64 folded = 0;
	assert(astra16_session_try_fold(object, INT64_C(-5000000000), UINT32_C(4000000000), 1.25f, 9, &folded, &error) && folded == INT64_C(-999999990) && !error);
	gboolean selected = TRUE;
	assert(astra16_session_try_choose(object, 7, &selected, &error) && !selected);
	gdouble result = 99;
	assert(!astra16_session_try_evaluate(object, -1, &result, &error) && result == 0 && error && error->domain == g_quark_from_static_string("astra-foreign-domain-16") && error->code == -1600);
	g_clear_error(&error);
	assert(astra16_session_try_evaluate(object, 4, &result, &error) && result == 10);
	callbacks_and_refs(object);
	payloads(object);
	records(object);
	objects(object);
	struct ThreadProbe probe = {object};
	GThread *thread = g_thread_new("astra16-context", wrong_thread, &probe);
	g_thread_join(thread);
	g_object_unref(object);
	assert(go16_destroyed_count() == 1);
	NativeHandle *root = NULL;
	NativeError native = {0, 0};
	assert(go16_native_create(3, true, 4.5, &root, &native) == 0 && root);
	object = astra16_session_as_gobject(root, &error);
	Astra16Session *again = astra16_session_as_gobject(root, &error);
	assert(object && again == object && !error);
	g_object_set(object, "count", 23, NULL);
	int32_t native_count = 0;
	assert(go16_native_get_count(root, &native_count, &native) == 0 && native_count == 23);
	assert(go16_native_native_only(root, 5, &native_count, &native) == 0 && native_count == 8);
	go16_native_release(root);
	g_object_unref(again);
	assert(go16_destroyed_count() == 1);
	g_object_unref(object);
	assert(go16_destroyed_count() == 2 && go16_item_destroyed_count() == 4);
	puts("PASS declared GObject scalar properties and native C identity");
	return 0;
}
