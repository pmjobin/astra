/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "gobject-signals.h"
#include "retained.h"
#include <limits.h>
#include <stdlib.h>
#include <string.h>

struct source {
	int32_t mode;
	GWeakRef object;
	guint signal;
};
struct connection {
	GObject *object;
	gulong handler;
	void *token;
	int destroyed;
};
static struct source *sources[64];
static int32_t next_mode = 1;
static int32_t live_connections;

static struct source *lookup(int32_t mode) {
	for (size_t i = 0; i < G_N_ELEMENTS(sources); i++)
		if (sources[i] && sources[i]->mode == mode) return sources[i];
	return NULL;
}

static gint signal_callback(GObject *object, gint value, gpointer data) {
	struct connection *connection = data;
	if (connection->object != object || connection->destroyed) return -3;
	return astra_retained_dispatch(connection->token, value);
}

static void destroyed(gpointer data, GClosure *closure) {
	(void)closure;
	struct connection *connection = data;
	connection->handler = 0;
	connection->destroyed = 1;
}

static void *open_connection(int32_t mode, void *token) {
	struct source *source = lookup(mode);
	if (!source) return NULL;
	GObject *object = g_weak_ref_get(&source->object);
	if (!object) return NULL;
	struct connection *connection = calloc(1, sizeof *connection);
	if (!connection) {
		g_object_unref(object);
		return NULL;
	}
	connection->object = object;
	connection->token = token;
	connection->handler = g_signal_connect_data(object, g_signal_name(source->signal),
	                                            G_CALLBACK(signal_callback), connection, destroyed, 0);
	if (!connection->handler) {
		g_object_unref(object);
		free(connection);
		return NULL;
	}
	live_connections++;
	return connection;
}

static int32_t stop_connection(void *data) {
	struct connection *connection = data;
	if (connection->handler) g_signal_handler_disconnect(connection->object, connection->handler);
	return 1;
}

static int32_t observe_connection(void *data) {
	struct connection *connection = data;
	return connection->destroyed == 1;
}

static int32_t close_connection(void *data) {
	struct connection *connection = data;
	if (!connection->destroyed || connection->handler) return 0;
	g_object_unref(connection->object);
	free(connection);
	live_connections--;
	return 1;
}

static const struct astra_retained_provider provider = {1, open_connection, stop_connection, observe_connection, close_connection};

void *astra_gobject_signal_source(void *token, const uint8_t *name, int32_t length) {
	GObject *object = astra_gobject_peek(token, G_TYPE_OBJECT);
	if (!object || !name || length <= 0 || memchr(name, 0, length) || !g_utf8_validate_len((const char *)name, length, NULL) || next_mode == INT32_MAX) return NULL;
	char *terminated = g_strndup((const char *)name, length);
	guint id = g_signal_lookup(terminated, G_OBJECT_TYPE(object));
	g_free(terminated);
	if (!id) return NULL;
	GSignalQuery query;
	g_signal_query(id, &query);
	if (query.return_type != G_TYPE_INT || query.n_params != 1 || query.param_types[0] != G_TYPE_INT || !g_type_is_a(G_OBJECT_TYPE(object), query.itype)) return NULL;
	if (astra_retained_install_provider(&provider) != 1) return NULL;
	for (size_t i = 0; i < G_N_ELEMENTS(sources); i++) {
		if (sources[i]) continue;
		struct source *source = calloc(1, sizeof *source);
		if (!source) return NULL;
		source->mode = next_mode++;
		source->signal = id;
		g_weak_ref_init(&source->object, object);
		sources[i] = source;
		return (void *)(uintptr_t)source->mode;
	}
	return NULL;
}

int32_t astra_gobject_signal_mode(void *token) {
	uintptr_t identity = (uintptr_t)token;
	return identity < INT32_MAX && lookup((int32_t)identity) ? (int32_t)identity : -1;
}

void astra_gobject_signal_source_free(void *token) {
	if (!token) return;
	int32_t mode = astra_gobject_signal_mode(token);
	struct source *source = lookup(mode);
	if (!source) abort();
	for (size_t i = 0; i < G_N_ELEMENTS(sources); i++)
		if (sources[i] == source) sources[i] = NULL;
	g_weak_ref_clear(&source->object);
	free(source);
}

int32_t astra_gobject_signal_connections(void) {
	return live_connections;
}
