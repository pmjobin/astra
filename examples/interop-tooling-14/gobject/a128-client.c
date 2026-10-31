/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "Astra128.h"
#include "a128-native.h"
#include <stdio.h>
extern int32_t a128_stats(int32_t);
static int listener_created, listener_closed, delivered, late, bad, weak_closed;
static astra128_publisher_handle *root;
typedef struct { int refs; gboolean dispose; } Listener;
static Listener *listener_new(gboolean dispose) { Listener *r = g_new0(Listener, 1); r->refs = 1; r->dispose = dispose; ++listener_created; return r; }
static Listener *listener_ref(Listener *r) { ++r->refs; return r; }
static void listener_unref(Listener *r) { if (--r->refs == 0) { ++listener_closed; g_free(r); } }
static void destroy_listener(gpointer data, GClosure *closure) { (void)closure; listener_unref(data); }
static void changed(Astra128Publisher *self, gint value, gpointer data) {
	Listener *listener = data; gboolean dispose = listener->dispose;
	int32_t actual = -1; if (astra128_publisher_get(root, &actual) != 0 || actual != value) ++bad;
	if ((delivered == 0 && value != 240) || (delivered == 1 && value != 261736)) ++bad;
	++delivered;
	if (dispose) g_object_run_dispose(G_OBJECT(self));
}
static void too_late(Astra128Publisher *self, gint value, gpointer data) { (void)self; (void)value; (void)data; ++late; }
static void weak_notify(gpointer data, GObject *dead) { (void)data; (void)dead; ++weak_closed; }
#define CHECK(test) do { if (!(test)) { printf("FAIL line=%d: %s\n", __LINE__, #test); return 1; } } while (0)
int main(void) {
	GError *error = NULL;
	root = astra128_publisher_create(0); CHECK(root);
	void *native = astra128_publisher_root_identity(root); CHECK(native && native != root);
	Astra128Publisher *object = astra128_publisher_as_gobject(root, &error); CHECK(object && !error);
	CHECK((void *)object != root && (void *)object != native);
	Astra128Publisher *same = astra128_publisher_as_gobject(root, &error); CHECK(same == object && !error); g_object_unref(same);
	g_object_weak_ref(G_OBJECT(object), weak_notify, NULL);
	astra128_publisher_weak_handle *weak = astra128_publisher_weak(root); CHECK(weak);
	Listener *listener = listener_new(FALSE);
	gulong id = g_signal_connect_data(object, "changed", G_CALLBACK(changed), listener_ref(listener), destroy_listener, 0);
	listener_unref(listener); CHECK(listener_created == 1 && listener_closed == 0);
	CHECK(astra128_publisher_set(root, 7) == 0 && delivered == 0);
	CHECK(astra128_publisher_try_set_value(object, 9, &error) && !error && delivered == 1 && bad == 0);
	g_signal_handler_disconnect(object, id); CHECK(listener_closed == 1);
	CHECK(astra128_publisher_try_set_value(object, 11, &error) && !error && delivered == 1);
	listener = listener_new(TRUE);
	g_signal_connect_data(object, "changed", G_CALLBACK(changed), listener_ref(listener), destroy_listener, 0); listener_unref(listener);
	listener = listener_new(FALSE);
	g_signal_connect_data(object, "changed", G_CALLBACK(too_late), listener_ref(listener), destroy_listener, 0); listener_unref(listener);
	CHECK(listener_created == 3 && listener_closed == 1);
	CHECK(astra128_publisher_try_set_value(object, 13, &error) && !error);
	CHECK(delivered == 2 && late == 0 && bad == 0 && listener_closed == 3 && a128_stats(1) == 0);
	gint out = 99; CHECK(!astra128_publisher_try_get_value(object, &out, &error) && out == 0 && error && error->code == 3); g_clear_error(&error);
	int32_t native_value = -1; CHECK(astra128_publisher_get(root, &native_value) == 0 && native_value == 261736);
	CHECK(astra128_publisher_set(root, 17) == 0 && delivered == 2);
	g_object_unref(object); CHECK(weak_closed == 1 && a128_stats(1) == 0);
	object = astra128_publisher_as_gobject(root, &error); CHECK(object && !error);
	g_object_weak_ref(G_OBJECT(object), weak_notify, NULL);
	CHECK(astra128_publisher_try_get_value(object, &out, &error) && !error && out == 637281);
	CHECK(astra128_publisher_root_identity(root) == native && astra128_publisher_release(root) == 1);
	g_object_unref(object);
	CHECK(weak_closed == 2 && a128_stats(0) == 1 && a128_stats(1) == 1 && a128_stats(2) == 637281 && a128_stats(3) == 5);
	CHECK(astra128_publisher_weak_upgrade(weak) == NULL); astra128_publisher_weak_release(weak);
	puts("PASS A128: C-GObject event-checksum=637281 retained-listener disconnect dispose-during-delivery quiescence stable-root recreated-view weak-expiry native-destroyed=1");
	return 0;
}
