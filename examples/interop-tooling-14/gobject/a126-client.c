/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "Astra126.h"
#include "a126-native.h"
#include <stdio.h>
extern int32_t a126_stats(int32_t);
static int changes, notifications, weak_notifications, bad;
static void changed(Astra126Settings *self, gint value, gpointer data) {
	(void)data; const int expected[] = {3, 7, 0}; gint actual = -1;
	if (changes >= 3 || value != expected[changes] || !astra126_settings_try_get_value(self, &actual, NULL) || actual != value) ++bad;
	++changes;
}
static void notified(GObject *self, GParamSpec *spec, gpointer data) { (void)self; (void)data; if (g_strcmp0(spec->name, "value")) ++bad; ++notifications; }
static void weak_notify(gpointer data, GObject *dead) { (void)data; (void)dead; ++weak_notifications; }
#define CHECK(test) do { if (!(test)) { printf("FAIL line=%d: %s\n", __LINE__, #test); return 1; } } while (0)
static gpointer worker(gpointer object) {
	gint out = 99; GError *error = NULL;
	int failed = astra126_settings_try_set_value(object, 5, &error) || !error || error->code != 2;
	g_clear_error(&error);
	failed |= astra126_settings_try_get_value(object, &out, &error) || out != 0 || !error || error->code != 2;
	g_clear_error(&error); return GINT_TO_POINTER(failed);
}
int main(void) {
	GError *error = NULL;
	astra126_settings_handle *root = astra126_settings_create(1); CHECK(root);
	Astra126Settings *object = astra126_settings_as_gobject(root, &error); CHECK(object && !error);
	Astra126Settings *same = astra126_settings_as_gobject(root, &error); CHECK(same == object && !error);
	g_object_unref(same); g_object_weak_ref(G_OBJECT(object), weak_notify, NULL);
	g_signal_connect(object, "changed", G_CALLBACK(changed), NULL);
	g_signal_connect(object, "notify::value", G_CALLBACK(notified), NULL);
	g_object_set(object, "value", 3, NULL);
	CHECK(astra126_settings_try_set_value(object, 7, &error) && !error);
	g_object_set(object, "value", 9, NULL); g_object_set(object, "value", 7, NULL);
	CHECK(changes == 2 && notifications == 2 && bad == 0);
	GThread *thread = g_thread_new("settings", worker, object); CHECK(g_thread_join(thread) == NULL);
	gint out = -1; g_object_get(object, "value", &out, NULL); CHECK(out == 7);
	g_object_set(object, "value", 0, NULL); g_object_set(object, "value", 0, NULL);
	CHECK(changes == 3 && notifications == 3 && bad == 0);
	GWeakRef weak; g_weak_ref_init(&weak, object);
	CHECK(astra126_settings_release(root) == 1 && a126_stats(1) == 0);
	g_object_unref(object);
	CHECK(g_weak_ref_get(&weak) == NULL && weak_notifications == 1); g_weak_ref_clear(&weak);
	CHECK(a126_stats(0) == 1 && a126_stats(1) == 1 && a126_stats(2) == 0 && a126_stats(3) == 5);
	puts("PASS A126: live-settings 3-signals 5-bit-revisions normalized-refused-settings stable-view wrong-thread restored weak-notify native-destroyed=1");
	return 0;
}
