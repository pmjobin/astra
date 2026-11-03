/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "counter.h"
#include <stdlib.h>

struct _AstCounter {
	GObject parent;
	gint value;
	char *label;
	gboolean disposed;
};

typedef struct {
	GObjectClass parent;
} AstCounterClass;
G_DEFINE_TYPE(AstCounter, ast_counter, G_TYPE_OBJECT)
static int disposed_count, finalized_count;
static guint changed_signal;

enum { PROP_NONE,
	   PROP_VALUE,
	   PROP_LABEL,
	   PROP_COUNT };

static GParamSpec *properties[PROP_COUNT];

static void counter_get_property(GObject *object, guint id, GValue *value, GParamSpec *spec) {
	AstCounter *self = (AstCounter *)object;
	switch (id) {
	case PROP_VALUE:
		g_value_set_int(value, self->value);
		break;
	case PROP_LABEL:
		g_value_set_string(value, self->label);
		break;
	default:
		G_OBJECT_WARN_INVALID_PROPERTY_ID(object, id, spec);
	}
}

static void counter_set_property(GObject *object, guint id, const GValue *value, GParamSpec *spec) {
	AstCounter *self = (AstCounter *)object;
	switch (id) {
	case PROP_VALUE:
		self->value = g_value_get_int(value);
		g_object_notify_by_pspec(object, properties[PROP_VALUE]);
		break;
	case PROP_LABEL:
		g_free(self->label);
		self->label = g_value_dup_string(value);
		g_object_notify_by_pspec(object, properties[PROP_LABEL]);
		break;
	default:
		G_OBJECT_WARN_INVALID_PROPERTY_ID(object, id, spec);
	}
}

static void counter_dispose(GObject *object) {
	AstCounter *self = (AstCounter *)object;
	if (!self->disposed) {
		self->disposed = TRUE;
		disposed_count++;
	}
	G_OBJECT_CLASS(ast_counter_parent_class)->dispose(object);
}

static void counter_finalize(GObject *object) {
	AstCounter *self = (AstCounter *)object;
	g_free(self->label);
	finalized_count++;
	G_OBJECT_CLASS(ast_counter_parent_class)->finalize(object);
}

static void ast_counter_class_init(AstCounterClass *klass) {
	GObjectClass *object = G_OBJECT_CLASS(klass);
	object->get_property = counter_get_property;
	object->set_property = counter_set_property;
	object->dispose = counter_dispose;
	object->finalize = counter_finalize;
	properties[PROP_VALUE] = g_param_spec_int("value", "Value", "Counted value", -10000, 10000, 0, G_PARAM_READWRITE | G_PARAM_EXPLICIT_NOTIFY);
	properties[PROP_LABEL] = g_param_spec_string("label", "Label", "UTF-8 label", "", G_PARAM_READWRITE | G_PARAM_EXPLICIT_NOTIFY);
	g_object_class_install_properties(object, PROP_COUNT, properties);
	changed_signal = g_signal_new("changed", G_TYPE_FROM_CLASS(klass), G_SIGNAL_RUN_LAST,
	                              0, NULL, NULL, NULL, G_TYPE_INT, 1, G_TYPE_INT);
}

static void ast_counter_init(AstCounter *self) {
	self->label = g_strdup("");
}

AstCounter *ast_counter_new(gint value) {
	if (value < -10000 || value > 10000) return NULL;
	return g_object_new(ast_counter_get_type(), "value", value, NULL);
}

gint ast_counter_read(AstCounter *self) {
	return self->disposed ? INT32_MIN : self->value;
}

gint ast_counter_write(AstCounter *self, gint value) {
	if (self->disposed || value < -10000 || value > 10000) return -1;
	g_object_set(self, "value", value, NULL);
	return 1;
}

const gchar *ast_counter_label(AstCounter *self) {
	return self->disposed ? NULL : self->label;
}

GObject *ast_counter_as_object(AstCounter *self) {
	return self->disposed ? NULL : g_object_ref(G_OBJECT(self));
}

gint ast_counter_emit(AstCounter *self, gint value) {
	if (self->disposed) return -3;
	gint result = 0;
	g_signal_emit(self, changed_signal, 0, value, &result);
	return result;
}

static AstCounter *counter(void *token) {
	AstCounter *self = (AstCounter *)astra_gobject_peek(token, ast_counter_get_type());
	return self && !self->disposed ? self : NULL;
}

void *counter_new(int32_t value) {
	return astra_gobject_take((GObject *)ast_counter_new(value), ast_counter_get_type());
}

int32_t counter_get(void *token) {
	int32_t value;
	return counter(token) && astra_gobject_get_int(token, "value", &value) == 1 ? value : INT32_MIN;
}

int32_t counter_set(void *token, int32_t value) {
	return counter(token) ? astra_gobject_set_int(token, "value", value) : -1;
}

int32_t counter_label(void *token, const uint8_t *text, int32_t length) {
	return counter(token) ? astra_gobject_set_utf8(token, "label", text, length) : -1;
}

void *counter_snapshot(void *token) {
	return counter(token) ? astra_gobject_copy_utf8(token, "label") : NULL;
}

int32_t counter_finalized(void) {
	return finalized_count;
}

int32_t counter_disposed(void) {
	return disposed_count;
}

int32_t counter_emit(void *token, int32_t value) {
	AstCounter *self = counter(token);
	if (!self) return -3;
	return ast_counter_emit(self, value);
}
