/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "gobject.h"
#include <limits.h>
#include <stdlib.h>
#include <string.h>

_Static_assert(sizeof(gint) == sizeof(int32_t), "GObject adapter requires exact C int32");
_Static_assert(sizeof(void *) == 8 && sizeof(GType) == 8, "GObject adapter profile requires LP64");

enum handle_kind { STRONG = 1,
	               WEAK,
	               TEXT };

struct foreign_handle {
	uintptr_t token;
	enum handle_kind kind;
	GType expected;
	GObject *object;
	GWeakRef weak;
	char *text;
};
static struct foreign_handle *handles[256];
static uintptr_t next_token = 1;
static guint next_identity = 1;

static struct foreign_handle *lookup(void *token, enum handle_kind kind) {
	for (size_t i = 0; i < G_N_ELEMENTS(handles); i++) {
		if (handles[i] && handles[i]->token == (uintptr_t)token && handles[i]->kind == kind) return handles[i];
	}
	return NULL;
}

static struct foreign_handle *reserve(enum handle_kind kind) {
	if (next_token == UINTPTR_MAX) return NULL;
	for (size_t i = 0; i < G_N_ELEMENTS(handles); i++) {
		if (handles[i]) continue;
		struct foreign_handle *entry = calloc(1, sizeof *entry);
		if (!entry) return NULL;
		entry->kind = kind;
		entry->token = next_token++;
		handles[i] = entry;
		return entry;
	}
	return NULL;
}

static void remove_handle(struct foreign_handle *entry) {
	for (size_t i = 0; i < G_N_ELEMENTS(handles); i++) {
		if (handles[i] == entry) {
			handles[i] = NULL;
			break;
		}
	}
	free(entry);
}

void *astra_gobject_take(GObject *object, GType expected) {
	if (!object) return NULL;
	if (!g_type_is_a(expected, G_TYPE_OBJECT) || !G_TYPE_CHECK_INSTANCE_TYPE(object, expected)) {
		g_object_unref(object);
		return NULL;
	}
	struct foreign_handle *entry = reserve(STRONG);
	if (!entry) {
		g_object_unref(object);
		return NULL;
	}
	entry->object = object;
	entry->expected = expected;
	return (void *)entry->token;
}

GObject *astra_gobject_peek(void *token, GType expected) {
	struct foreign_handle *entry = lookup(token, STRONG);
	if (!entry || !g_type_is_a(entry->expected, expected) || !G_TYPE_CHECK_INSTANCE_TYPE(entry->object, expected)) return NULL;
	return entry->object;
}

void *astra_gobject_ref(void *token) {
	struct foreign_handle *entry = lookup(token, STRONG);
	if (!entry) return NULL;
	return astra_gobject_take(g_object_ref(entry->object), entry->expected);
}

int32_t astra_gobject_release_checked(void *token) {
	struct foreign_handle *entry = lookup(token, STRONG);
	if (!entry) return -1;
	GObject *object = entry->object;
	remove_handle(entry);
	g_object_unref(object);
	return 1;
}

void astra_gobject_unref(void *token) {
	if (token && astra_gobject_release_checked(token) != 1) abort();
}

int32_t astra_gobject_identity(void *token) {
	struct foreign_handle *entry = lookup(token, STRONG);
	if (!entry) return 0;
	GQuark key = g_quark_from_static_string("astra-foreign-identity-v1");
	guint identity = GPOINTER_TO_UINT(g_object_get_qdata(entry->object, key));
	if (!identity) {
		if (next_identity == INT32_MAX) return 0;
		identity = next_identity++;
		g_object_set_qdata(entry->object, key, GUINT_TO_POINTER(identity));
	}
	return (int32_t)identity;
}

int32_t astra_gobject_same(void *left, void *right) {
	struct foreign_handle *a = lookup(left, STRONG), *b = lookup(right, STRONG);
	return a && b && a->object == b->object;
}

void *astra_gobject_weak(void *token) {
	struct foreign_handle *owner = lookup(token, STRONG);
	if (!owner) return NULL;
	struct foreign_handle *entry = reserve(WEAK);
	if (!entry) return NULL;
	entry->expected = owner->expected;
	g_weak_ref_init(&entry->weak, owner->object);
	return (void *)entry->token;
}

void *astra_gobject_upgrade(void *token) {
	struct foreign_handle *entry = lookup(token, WEAK);
	if (!entry) return NULL;
	return astra_gobject_take(g_weak_ref_get(&entry->weak), entry->expected);
}

void astra_gobject_weak_free(void *token) {
	if (!token) return;
	struct foreign_handle *entry = lookup(token, WEAK);
	if (!entry) abort();
	g_weak_ref_clear(&entry->weak);
	remove_handle(entry);
}

static GParamSpec *property(GObject *object, const char *name, GType type, GParamFlags access) {
	if (!object || !name) return NULL;
	GParamSpec *spec = g_object_class_find_property(G_OBJECT_GET_CLASS(object), name);
	return spec && G_PARAM_SPEC_VALUE_TYPE(spec) == type && (spec->flags & access) == access ? spec : NULL;
}

int32_t astra_gobject_set_int(void *token, const char *name, int32_t value) {
	GObject *object = astra_gobject_peek(token, G_TYPE_OBJECT);
	GParamSpec *spec = property(object, name, G_TYPE_INT, G_PARAM_WRITABLE);
	if (!spec || (spec->flags & G_PARAM_CONSTRUCT_ONLY)) return -1;
	GParamSpecInt *integer = G_PARAM_SPEC_INT(spec);
	if (value < integer->minimum || value > integer->maximum) return -1;
	g_object_set(object, name, (gint)value, NULL);
	return 1;
}

int32_t astra_gobject_get_int(void *token, const char *name, int32_t *result) {
	GObject *object = astra_gobject_peek(token, G_TYPE_OBJECT);
	if (!result || !property(object, name, G_TYPE_INT, G_PARAM_READABLE)) return -1;
	gint value;
	g_object_get(object, name, &value, NULL);
	*result = value;
	return 1;
}

int32_t astra_gobject_set_utf8(void *token, const char *name, const uint8_t *text, int32_t length) {
	GObject *object = astra_gobject_peek(token, G_TYPE_OBJECT);
	GParamSpec *spec = property(object, name, G_TYPE_STRING, G_PARAM_WRITABLE);
	if (!spec || (spec->flags & G_PARAM_CONSTRUCT_ONLY) || length < 0 || (!text && length) ||
	    (length && (memchr(text, 0, (size_t)length) || !g_utf8_validate_len((const char *)text, length, NULL)))) return -1;
	char *copy = g_strndup(length ? (const char *)text : "", (gsize)length);
	g_object_set(object, name, copy, NULL);
	g_free(copy);
	return 1;
}

void *astra_gobject_copy_utf8(void *token, const char *name) {
	GObject *object = astra_gobject_peek(token, G_TYPE_OBJECT);
	if (!property(object, name, G_TYPE_STRING, G_PARAM_READABLE)) return NULL;
	char *copy = NULL;
	g_object_get(object, name, &copy, NULL);
	if (!copy || !g_utf8_validate(copy, -1, NULL) || strlen(copy) > INT32_MAX) {
		g_free(copy);
		return NULL;
	}
	struct foreign_handle *entry = reserve(TEXT);
	if (!entry) {
		g_free(copy);
		return NULL;
	}
	entry->text = copy;
	return (void *)entry->token;
}

void *astra_gobject_copy_text(const char *text) {
	if (!text || !g_utf8_validate(text, -1, NULL) || strlen(text) > INT32_MAX) return NULL;
	struct foreign_handle *entry = reserve(TEXT);
	if (!entry) return NULL;
	entry->text = g_strdup(text);
	return (void *)entry->token;
}

int32_t astra_gobject_text_length(void *token) {
	struct foreign_handle *entry = lookup(token, TEXT);
	return entry ? (int32_t)strlen(entry->text) : -1;
}

int32_t astra_gobject_text_byte(void *token, int32_t offset) {
	struct foreign_handle *entry = lookup(token, TEXT);
	if (!entry || offset < 0 || (size_t)offset >= strlen(entry->text)) return -1;
	return (unsigned char)entry->text[offset];
}

void astra_gobject_text_free(void *token) {
	if (!token) return;
	struct foreign_handle *entry = lookup(token, TEXT);
	if (!entry) abort();
	g_free(entry->text);
	remove_handle(entry);
}

int32_t astra_gobject_live_handles(void) {
	int32_t result = 0;
	for (size_t i = 0; i < G_N_ELEMENTS(handles); i++)
		if (handles[i]) result++;
	return result;
}
