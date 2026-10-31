/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "gobject-signals-16.h"
#include <limits.h>
#include <string.h>

#if !defined(__linux__) || !defined(__x86_64__)
#error "typed retained signal runtime requires qualified GNU x86-64 Linux"
#endif
_Static_assert(sizeof(void *) == 8 && sizeof(GType) == 8 && sizeof(gint) == 4 && sizeof(gboolean) == 4 && sizeof(gfloat) == 4 && sizeof(gdouble) == 8, "typed GObject signal transport layout");

extern uint64_t astra_foreign14_thread_identity(void);
struct signal_source {
	struct signal_source *next;
	GWeakRef object;
	uint64_t thread;
	int32_t mode;
	guint signal;
	char *signature;
	GClosureMarshal marshal;
};
struct signal_connection {
	struct signal_connection *next;
	uintptr_t identity;
	uint64_t thread;
	GObject *object;
	gulong handler;
	void (*callback)(void);
	void *context;
	gboolean active, stopped, foreign_retired;
};
static GMutex registry;
static struct signal_source *sources;
static struct signal_connection *connections;
static int32_t next_mode = 1;
static uintptr_t next_identity = 1;
static uint64_t reentry_refusals;

/* Wrong-thread and stale-token checks finish while the registry lock protects
 * lookup. Only the constructing thread then touches connection state. */
static struct signal_connection *lookup(void *token) {
	uint64_t thread = astra_foreign14_thread_identity();
	struct signal_connection *found = NULL;
	g_mutex_lock(&registry);
	for (struct signal_connection *c = connections; c; c = c->next) {
		if (c->identity == (uintptr_t)token && c->thread == thread) {
			found = c;
			break;
		}
	}
	g_mutex_unlock(&registry);
	return found;
}
static void invalidated(gpointer data, GClosure *closure) {
	(void)closure;
	struct signal_connection *c = data;
	if (c->thread != astra_foreign14_thread_identity()) {
		g_error("signal invalidation requires its constructing thread");
	}
	c->stopped = TRUE;
	c->handler = 0;
}
static void finalized(gpointer data, GClosure *closure) {
	(void)closure;
	struct signal_connection *c = data;
	if (c->thread != astra_foreign14_thread_identity() || c->active) {
		g_error("signal closure finalized before quiescence");
	}
	c->stopped = TRUE;
	c->handler = 0;
	c->foreign_retired = TRUE;
}
void *astra_gobject16_signal_source(GObject *object, const char *name, const char *signature, GClosureMarshal marshal, guint count, const GType *types) {
	if (!object || !G_IS_OBJECT(object) || g_object_is_floating(object) || !name || !g_signal_is_valid_name(name) || !signature || strlen(signature) > 65536 || !marshal || count > 256 || (count && !types)) {
		return NULL;
	}
	guint id = g_signal_lookup(name, G_OBJECT_TYPE(object));
	GSignalQuery query = {0};
	g_signal_query(id, &query);
	if (!id || query.return_type != G_TYPE_NONE || query.n_params != count || !g_type_is_a(G_OBJECT_TYPE(object), query.itype) || (query.signal_flags & (G_SIGNAL_RUN_FIRST | G_SIGNAL_RUN_LAST | G_SIGNAL_RUN_CLEANUP)) != G_SIGNAL_RUN_LAST) {
		return NULL;
	}
	for (guint i = 0; i < count; i++) {
		if (query.param_types[i] != types[i]) {
			return NULL;
		}
	}
	struct signal_source *s = g_try_new0(struct signal_source, 1);
	if (!s) {
		return NULL;
	}
	size_t signature_bytes = strlen(signature) + 1;
	s->signature = g_try_malloc(signature_bytes);
	if (!s->signature) {
		g_free(s);
		return NULL;
	}
	memcpy(s->signature, signature, signature_bytes);
	s->thread = astra_foreign14_thread_identity();
	s->signal = id;
	s->marshal = marshal;
	g_weak_ref_init(&s->object, object);
	g_mutex_lock(&registry);
	if (next_mode == INT32_MAX) {
		g_mutex_unlock(&registry);
		g_weak_ref_clear(&s->object);
		g_free(s->signature);
		g_free(s);
		return NULL;
	}
	s->mode = next_mode++;
	s->next = sources;
	sources = s;
	g_mutex_unlock(&registry);
	return s;
}
int32_t astra_gobject16_signal_mode(void *source) {
	uint64_t thread = astra_foreign14_thread_identity();
	int32_t mode = -1;
	g_mutex_lock(&registry);
	for (struct signal_source *s = sources; s; s = s->next) {
		if (s == source && s->thread == thread) {
			mode = s->mode;
			break;
		}
	}
	g_mutex_unlock(&registry);
	return mode;
}
void astra_gobject16_signal_source_free(void *source) {
	if (!source) {
		return;
	}
	uint64_t thread = astra_foreign14_thread_identity();
	struct signal_source *found = NULL;
	g_mutex_lock(&registry);
	for (struct signal_source **p = &sources; *p; p = &(*p)->next) {
		if (*p == source && (*p)->thread == thread) {
			found = *p;
			*p = found->next;
			break;
		}
	}
	g_mutex_unlock(&registry);
	if (!found) {
		g_error("invalid signal source retirement");
	}
	g_weak_ref_clear(&found->object);
	g_free(found->signature);
	g_free(found);
}
void *astra_gobject16_signal_register(void (*callback)(void), void *context, int32_t mode, const char *signature) {
	if (!callback || !context || mode <= 0 || !signature) {
		return NULL;
	}
	uint64_t thread = astra_foreign14_thread_identity();
	GObject *object = NULL;
	GClosureMarshal marshal = NULL;
	guint signal = 0;
	uintptr_t identity = 0;
	g_mutex_lock(&registry);
	for (struct signal_source *s = sources; s; s = s->next) {
		if (s->mode == mode && s->thread == thread && strcmp(signature, s->signature) == 0 && next_identity != UINTPTR_MAX) {
			object = g_weak_ref_get(&s->object);
			marshal = s->marshal;
			signal = s->signal;
			identity = next_identity++;
			break;
		}
	}
	g_mutex_unlock(&registry);
	if (!object) {
		return NULL;
	}
	struct signal_connection *c = g_try_new0(struct signal_connection, 1);
	if (!c) {
		g_object_unref(object);
		return NULL;
	}
	c->identity = identity;
	c->thread = thread;
	c->object = object;
	c->callback = callback;
	c->context = context;
	GClosure *closure = g_closure_new_simple(sizeof(GClosure), c);
	g_closure_ref(closure);
	g_closure_sink(closure);
	g_closure_set_marshal(closure, marshal);
	g_closure_add_invalidate_notifier(closure, c, invalidated);
	g_closure_add_finalize_notifier(closure, c, finalized);
	c->handler = g_signal_connect_closure_by_id(object, signal, 0, closure, FALSE);
	g_closure_unref(closure);
	if (!c->handler) {
		g_object_unref(object);
		g_free(c);
		return NULL;
	}
	g_mutex_lock(&registry);
	c->next = connections;
	connections = c;
	g_mutex_unlock(&registry);
	return (void *)identity;
}
int32_t astra_gobject16_signal_revoke(void *token) {
	struct signal_connection *c = lookup(token);
	if (!c) {
		return -3;
	}
	c->stopped = TRUE;
	gulong handler = c->handler;
	c->handler = 0;
	if (handler) {
		g_signal_handler_disconnect(c->object, handler);
	}
	return 1;
}
int32_t astra_gobject16_signal_observe(void *token) {
	struct signal_connection *c = lookup(token);
	if (!c) {
		return -3;
	}
	return c->stopped && !c->active && c->foreign_retired ? 1 : 0;
}
int32_t astra_gobject16_signal_retire(void *token) {
	struct signal_connection *c = lookup(token);
	if (!c || c->active) {
		return 0;
	}
	if (astra_gobject16_signal_revoke(token) != 1 || astra_gobject16_signal_observe(token) != 1) {
		return 0;
	}
	g_mutex_lock(&registry);
	for (struct signal_connection **p = &connections; *p; p = &(*p)->next) {
		if (*p == c) {
			*p = c->next;
			break;
		}
	}
	g_mutex_unlock(&registry);
	GObject *object = c->object;
	c->callback = NULL;
	c->context = NULL;
	g_free(c);
	g_object_unref(object);
	return 1;
}
int32_t astra_gobject16_signal_enter(void *data) {
	struct signal_connection *c = data;
	if (!c || lookup((void *)c->identity) != c || c->stopped || c->foreign_retired) {
		return -3;
	}
	if (c->active) {
		g_mutex_lock(&registry);
		++reentry_refusals;
		g_mutex_unlock(&registry);
		return -2;
	}
	c->active = TRUE;
	return 1;
}
void astra_gobject16_signal_leave(void *data) {
	struct signal_connection *c = data;
	if (!c || lookup((void *)c->identity) != c || !c->active) {
		g_error("invalid active signal retirement");
	}
	c->active = FALSE;
}
void (*astra_gobject16_signal_callback(void *data))(void) {
	struct signal_connection *c = data;
	return c && c->active && c->thread == astra_foreign14_thread_identity() ? c->callback : NULL;
}
void *astra_gobject16_signal_context(void *data) {
	struct signal_connection *c = data;
	return c && c->active && c->thread == astra_foreign14_thread_identity() ? c->context : NULL;
}
int32_t astra_gobject16_signal_connections(void) {
	int32_t count = 0;
	g_mutex_lock(&registry);
	for (struct signal_connection *c = connections; c; c = c->next) {
		if (count == INT32_MAX) {
			break;
		}
		++count;
	}
	g_mutex_unlock(&registry);
	return count;
}
uint64_t astra_gobject16_signal_reentry_refusals(void) {
	g_mutex_lock(&registry);
	uint64_t result = reentry_refusals;
	g_mutex_unlock(&registry);
	return result;
}
