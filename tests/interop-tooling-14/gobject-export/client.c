// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include "gobject14.h"
#include "counter.h"
#include <stdint.h>
#include <stdio.h>
extern int32_t astra14_stats(int32_t index);
extern void astra14_fault(int32_t allocator, int32_t after);
static int changed;
static int notified;
static int callback_bad;
static int disposed_callback;
static int late_callback;
static astra14_counter_handle *observed_root;
#define CHECK(test) do { if (!(test)) { printf("FAIL line=%d: %s\n", __LINE__, #test); return 1; } } while (0)
static void on_changed(Astra14Counter *self, gint value, gpointer context) {
	(void)context; gint actual = 0; int32_t native = 0;
	if (!astra14_counter_try_get_value(self, &actual, NULL) || actual != value || astra14_counter_get(observed_root, &native) != 0 || native != value) ++callback_bad;
	++changed;
}
static void on_notify(GObject *self, GParamSpec *spec, gpointer context) { (void)self; (void)context; if (g_strcmp0(spec->name, "value")) ++callback_bad; ++notified; }
static void drop_owner(Astra14Counter *self, gint value, gpointer context) { (void)value; (void)context; g_object_unref(self); }
static void dispose_during_signal(Astra14Counter *self, gint value, gpointer context) {
	(void)value; (void)context; GError *error = NULL; gint out = 99;
	g_object_run_dispose(G_OBJECT(self));
	if (astra14_counter_try_get_value(self, &out, &error) || out != 0 || !error || error->code != 3) ++callback_bad;
	g_clear_error(&error); ++disposed_callback;
}
static void too_late(Astra14Counter *self, gint value, gpointer context) { (void)self; (void)value; (void)context; ++late_callback; }
struct Worker { Astra14Counter *object; astra14_counter_handle *root; };
static int worker_check(struct Worker *context) {
	g_object_ref(context->object);
	gint out = 99; GError *error = NULL;
	CHECK(!astra14_counter_try_get_value(context->object, &out, &error) && out == 0 && error && error->code == 2); g_clear_error(&error);
	CHECK(!astra14_counter_try_set_value(context->object, 88, &error) && error && error->code == 2); g_clear_error(&error);
	CHECK(astra14_counter_as_gobject(context->root, &error) == NULL && error && error->code == 2); g_clear_error(&error);
	g_object_get(context->object, "value", &out, NULL); CHECK(out == 0);
	g_object_set(context->object, "value", 88, NULL);
	g_object_unref(context->object); return 0;
}
static gpointer worker(gpointer data) { return GINT_TO_POINTER(worker_check(data)); }
static gpointer last_unref(gpointer data) { g_object_unref(data); return NULL; }
int main(void) {
	GError *error = NULL; gint out = 99;
	CHECK(g_type_is_a(astra14_counter_get_type(), G_TYPE_OBJECT));
	CHECK(!astra14_counter_try_get_value(NULL, &out, &error) && out == 0 && error && error->code == 1); g_clear_error(&error);
	astra14_counter_handle *root = astra14_counter_create(40); CHECK(root);
	Astra14Counter *object = astra14_counter_as_gobject(root, &error); CHECK(object && !error && !g_object_is_floating(object));
	CHECK((void *)object != (void *)root && (void *)object != astra14_counter_root_identity(root));
	Astra14Counter *again = astra14_counter_as_gobject(root, &error); CHECK(again == object && !error);
	g_object_ref_sink(object); g_object_unref(again); g_object_unref(object);
	CHECK(astra14_counter_acquire(root) == 3 && astra14_counter_release(root) == 2);
	g_object_get(object, "value", &out, NULL); CHECK(out == 40);
	CHECK(astra14_counter_set(root, 17) == 0);
	g_object_get(object, "value", &out, NULL); CHECK(out == 17);
	observed_root = root;
	g_signal_connect(object, "changed", G_CALLBACK(on_changed), NULL);
	g_signal_connect(object, "notify::value", G_CALLBACK(on_notify), NULL);
	g_object_set(object, "value", 25, NULL);
	CHECK(changed == 1 && notified == 1 && !callback_bad);
	g_object_set(object, "value", 25, NULL); CHECK(changed == 1 && notified == 1);
	GWeakRef object_weak; g_weak_ref_init(&object_weak, object);
	astra14_counter_weak_handle *weak = astra14_counter_weak(root); CHECK(weak);
	CHECK(astra14_counter_release(root) == 1 && astra14_stats(1) == 0);
	g_object_unref(object);
	CHECK(g_weak_ref_get(&object_weak) == NULL && astra14_counter_weak_upgrade(weak) == NULL);
	g_weak_ref_clear(&object_weak); astra14_counter_weak_release(weak);
	CHECK(astra14_stats(0) == 1 && astra14_stats(1) == 1 && astra14_stats(3) == 25);
	puts("PASS real GType property signal non-floating-ref-sink distinct-C-GObject-native identities one-root weak-expiry");
	root = astra14_counter_create(40); object = astra14_counter_as_gobject(root, &error); CHECK(object && !error);
	g_object_run_dispose(G_OBJECT(object));
	CHECK(!astra14_counter_try_get_value(object, &out, &error) && out == 0 && error && error->code == 3); g_clear_error(&error);
	CHECK(astra14_counter_as_gobject(root, &error) == NULL && error && error->code == 3); g_clear_error(&error);
	g_object_unref(object); CHECK(astra14_stats(0) == 2 && astra14_stats(1) == 1);
	object = astra14_counter_as_gobject(root, &error); CHECK(object && !error && astra14_stats(0) == 2);
	CHECK(astra14_counter_release(root) == 1); g_object_unref(object);
	CHECK(astra14_stats(1) == 2 && astra14_stats(3) == 40);
	object = astra14_counter_new(9, &error); CHECK(object && !error);
	g_weak_ref_init(&object_weak, object);
	g_signal_connect(object, "changed", G_CALLBACK(drop_owner), NULL);
	CHECK(astra14_counter_try_set_value(object, 11, &error) && !error);
	CHECK(g_weak_ref_get(&object_weak) == NULL && astra14_stats(1) == 3 && astra14_stats(3) == 11); g_weak_ref_clear(&object_weak);
	object = astra14_counter_new(9, &error); CHECK(object && !error);
	g_signal_connect(object, "changed", G_CALLBACK(dispose_during_signal), NULL);
	g_signal_connect(object, "changed", G_CALLBACK(too_late), NULL);
	CHECK(astra14_counter_try_set_value(object, 14, &error) && !error);
	CHECK(disposed_callback == 1 && late_callback == 0 && callback_bad == 0 && astra14_stats(1) == 3);
	g_object_unref(object); CHECK(astra14_stats(1) == 4 && astra14_stats(3) == 14);
	object = g_object_new(astra14_counter_get_type(), "value", 31, NULL);
	CHECK(object && astra14_stats(0) == 5 && astra14_stats(2) == 0);
	CHECK(astra14_counter_try_get_value(object, &out, &error) && !error && out == 31);
	g_object_unref(object); CHECK(astra14_stats(1) == 5 && astra14_stats(3) == 31);
	puts("PASS GObject dispose-quiescence callback-owner-drop direct-GType-construction cached-view-recreation exact-native-cleanup");
	root = astra14_counter_create(40); object = astra14_counter_as_gobject(root, &error); CHECK(object && !error);
	struct Worker context = {object, root}; GThread *thread = g_thread_new("foreign14", worker, &context);
	CHECK(g_thread_join(thread) == NULL && changed == 1 && notified == 1);
	CHECK(astra14_counter_try_get_value(object, &out, &error) && !error && out == 40);
	g_object_unref(object); CHECK(astra14_counter_release(root) == 0 && astra14_stats(1) == 6);
	for (int i = 0; i < 128; ++i) {
		root = astra14_counter_create(40); object = astra14_counter_as_gobject(root, &error); CHECK(object && !error);
		thread = g_thread_new("retire14", last_unref, object);
		for (int n = 0; n < 8; ++n) {
			again = astra14_counter_as_gobject(root, &error);
			if (again) { CHECK(!error); g_object_unref(again); }
			else { CHECK(error && error->code == 3); g_clear_error(&error); }
		}
		CHECK(g_thread_join(thread) == NULL);
		object = astra14_counter_as_gobject(root, &error); CHECK(object && !error);
		CHECK(astra14_counter_release(root) == 1); g_object_unref(object);
		CHECK(astra14_stats(0) == i + 7 && astra14_stats(1) == i + 7);
	}
	puts("PASS GObject constructing-thread refusal restored-data 128-weak-cache-retirement-races exact-teardown");
	int before = astra14_stats(0); CHECK(astra14_stats(1) == before);
	astra14_fault(0, 1);
	CHECK(astra14_counter_new(40, &error) == NULL && error && error->code == 4); g_clear_error(&error);
	CHECK(astra14_stats(0) == before && astra14_stats(1) == before);
	astra14_fault(0, 2);
	CHECK(astra14_counter_new(40, &error) == NULL && error && error->code == 4); g_clear_error(&error);
	CHECK(astra14_stats(0) == before + 1 && astra14_stats(1) == before + 1 && astra14_stats(3) == 40);
	astra14_fault(1, 1);
	CHECK(astra14_counter_new(40, &error) == NULL && error && error->code == 4); g_clear_error(&error);
	CHECK(astra14_stats(0) == before + 2 && astra14_stats(1) == before + 2 && astra14_stats(3) == 40);
	root = astra14_counter_create(40); CHECK(root); astra14_fault(1, 1);
	CHECK(astra14_counter_as_gobject(root, &error) == NULL && error && error->code == 4); g_clear_error(&error);
	CHECK(astra14_counter_acquire(root) == 2 && astra14_counter_release(root) == 1);
	object = astra14_counter_as_gobject(root, &error); CHECK(object && !error); g_object_unref(object);
	CHECK(astra14_counter_release(root) == 0 && astra14_stats(0) == before + 3 && astra14_stats(1) == before + 3);
	puts("PASS GObject root-control-cache allocation failures partial-native-cleanup restored-adaptation");
	return 0;
}
