// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include "bridge.h"
#include <stdint.h>
#include <assert.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>

struct _Provider16Ledger {
	GObject parent_instance;
	gint seed;
	gboolean active;
	gdouble gain;
};
G_DEFINE_FINAL_TYPE(Provider16Ledger, provider16_ledger, G_TYPE_OBJECT)
static guint destroyed, errors, item_destroyed, record_retired, callback_environments;

int32_t gi16_callback_environment_retired(void) {
	return (int32_t)++callback_environments;
}

static void provider16_ledger_finalize(GObject *object) {
	++destroyed;
	G_OBJECT_CLASS(provider16_ledger_parent_class)->finalize(object);
}

static void provider16_ledger_class_init(Provider16LedgerClass *klass) {
	G_OBJECT_CLASS(klass)->finalize = provider16_ledger_finalize;
}

static void provider16_ledger_init(Provider16Ledger *self) {
	(void)self;
}

Provider16Ledger *provider16_ledger_new(gint seed, gboolean active, gdouble gain, GError **error) {
	if (seed == -2) return NULL;
	if (seed == -4) return (Provider16Ledger *)g_object_new(G_TYPE_OBJECT, NULL);
	Provider16Ledger *value = g_object_new(provider16_ledger_get_type(), NULL);
	if (seed == -1) {
		g_set_error_literal(error, g_quark_from_static_string("astra-foreign-domain-16"), -1600, "provisional constructor failure");
	}
	if (seed == -3) g_object_force_floating(G_OBJECT(value));
	value->seed = seed;
	value->active = active;
	value->gain = gain;
	return value;
}

gboolean provider16_ledger_try_fold(Provider16Ledger *self, gint64 input, guint mask, gfloat weight, guint64 stamp, gint64 *result, GError **error) {
	(void)error;
	*result = input + mask + (gint64)weight + (gint64)stamp + self->seed;
	return TRUE;
}

gboolean provider16_ledger_try_get_gain(Provider16Ledger *self, gdouble *result, GError **error) {
	(void)error;
	*result = self->gain;
	return TRUE;
}

gboolean provider16_ledger_try_set_gain(Provider16Ledger *self, gdouble value, GError **error) {
	(void)error;
	self->gain = value;
	return TRUE;
}

gboolean provider16_ledger_try_choose(Provider16Ledger *self, gboolean input, gboolean *result, GError **error) {
	(void)error;
	assert(input == TRUE || input == FALSE);
	*result = self->active && input ? 7 : FALSE;
	return TRUE;
}

gboolean provider16_ledger_try_evaluate(Provider16Ledger *self, gdouble input, gdouble *result, GError **error) {
	*result = 999;
	if (input < 0) {
		g_set_error_literal(error, g_quark_from_static_string("astra-foreign-domain-16"), -1600, "independent provider refusal");
		return FALSE;
	}
	*result = input * self->gain;
	return TRUE;
}

gboolean provider16_ledger_try_refs(Provider16Ledger *self, gint64 input, gdouble *scale, guint *count, gboolean fail, gint64 *result, GError **error) {
	(void)self;
	*result = input + 5;
	*scale += 1.5;
	*count = 4000000000u;
	if (fail) {
		g_set_error_literal(error, g_quark_from_static_string("astra-foreign-domain-16"), -1600, "staged reference failure");
		return FALSE;
	}
	return TRUE;
}

static guint deliveries;

void gi16_receive_double(double input) {
	assert(input == 1.25);
	++deliveries;
}

gboolean provider16_ledger_try_visit(Provider16Ledger *self, gboolean input, Provider16FlagCallback callback, gpointer data, gboolean *result, GError **error) {
	(void)self;
	(void)error;
	gboolean value = callback(data, input ? 7 : FALSE);
	assert(value == TRUE || value == FALSE);
	*result = value ? 7 : FALSE;
	return TRUE;
}

gboolean provider16_ledger_try_optional_visit(Provider16Ledger *self, gboolean input, Provider16FlagCallback callback, gpointer data, gboolean *result, GError **error) {
	if (callback) return provider16_ledger_try_visit(self, input, callback, data, result, error);
	*result = input;
	return TRUE;
}

gboolean provider16_ledger_try_deliver(Provider16Ledger *self, gdouble input, Provider16SinkCallback callback, gpointer data, GError **error) {
	(void)self;
	(void)error;
	callback(data, input);
	return TRUE;
}

static guint byte_retirements;

static void retired_bytes(gpointer value) {
	++byte_retirements;
	g_free(value);
}

static GBytes *owned_bytes(const guint8 *data, gsize count) {
	guint8 *copy = g_malloc(count ? count : 1);
	if (count) memcpy(copy, data, count);
	return g_bytes_new_with_free_func(copy, count, retired_bytes, copy);
}

gboolean provider16_ledger_try_digest(Provider16Ledger *self, GBytes *input, gint *result, GError **error) {
	(void)self;
	(void)error;
	gsize count = 0;
	const guint8 *data = g_bytes_get_data(input, &count);
	*result = 0;
	for (gsize i = 0; i < count; ++i)
		*result += data[i];
	return TRUE;
}

gboolean provider16_ledger_try_snapshot(Provider16Ledger *self, GBytes *input, gint mode, GBytes **result, GError **error) {
	(void)self;
	gsize count = 0;
	const guint8 *data = g_bytes_get_data(input, &count);
	if (mode == 2) {
		*result = NULL;
		return TRUE;
	}
	guint8 *copy = g_malloc(count ? count : 1);
	for (gsize i = 0; i < count; ++i)
		copy[i] = data[i] ^ 85;
	*result = g_bytes_new_with_free_func(copy, count, retired_bytes, copy);
	if (mode == 1) {
		g_set_error_literal(error, g_quark_from_static_string("astra-foreign-domain-16"), -1600, "provisional bytes failure");
		return FALSE;
	}
	return TRUE;
}

gboolean provider16_ledger_try_text(Provider16Ledger *self, gint mode, GBytes **result, GError **error) {
	(void)self;
	(void)error;
	const guint8 good[] = {97, 0, 195, 169}, bad[] = {255};
	*result = owned_bytes(mode ? bad : good, mode ? 1 : 4);
	return TRUE;
}

gboolean provider16_ledger_try_measure(Provider16Ledger *self, gchar *terminated, GBytes *counted, gint *result, GError **error) {
	(void)self;
	(void)error;
	assert(g_bytes_get_size(counted) == 4);
	*result = (gint)strlen(terminated) + (gint)g_bytes_get_size(counted);
	return TRUE;
}

gboolean provider16_ledger_try_transform(Provider16Ledger *self, GBytes *input, guint8 **output, gint *capacity, gint mode, gint *result, GError **error) {
	(void)self;
	gsize count = 0;
	const guint8 *data = g_bytes_get_data(input, &count);
	assert(*capacity == 4);
	if (mode) {
		(*output)[0] = 55;
		*result = 1;
		if (mode == 1) {
			g_set_error_literal(error, g_quark_from_static_string("astra-foreign-domain-16"), -1600, "output rollback");
			return FALSE;
		}
		if (mode == 2) *result = *capacity + 1;
		if (mode == 3) {
			static guint8 other[4];
			*output = other;
		}
		if (mode == 4) --*capacity;
		return TRUE;
	}
	assert(count <= 4);
	for (gsize i = 0; i < count; ++i)
		(*output)[i] = data[i] + 1;
	*result = (gint)count;
	return TRUE;
}

int32_t gi16_exception_retired(void) {
	return (int32_t)++errors;
}
typedef struct go16_import_handle ImportedHandle;
typedef struct gi16_consumer_handle NativeConsumer;
typedef struct gi16_item_handle ImportedItem;
typedef astra_foreign_error ForeignError;
extern int32_t go16_import_create(int32_t, bool, double, ImportedHandle **, ForeignError *);
extern uint32_t go16_import_release(ImportedHandle *);
extern int32_t gi16_item_create(int32_t, ImportedItem **, ForeignError *);
extern uint32_t gi16_item_release(ImportedItem *);
extern int32_t go16_import_take(ImportedHandle *, ImportedItem **, int32_t, int32_t *, ForeignError *);
extern int32_t gi16_consumer_create(NativeConsumer **, ForeignError *);
extern int32_t gi16_consumer_inspect(NativeConsumer *, ImportedHandle *, int64_t *, ForeignError *);
extern int32_t gi16_consumer_destroy(NativeConsumer **, ForeignError *);
static ImportedHandle *active_owner;

int32_t gi16_release_current(void) {
	assert(active_owner);
	go16_import_release(active_owner);
	active_owner = NULL;
	assert(destroyed == 3);
	return 0;
}

static gpointer wrong_context(gpointer data) {
	NativeConsumer *consumer = NULL;
	ForeignError error = {0, 0};
	assert(!gi16_consumer_create(&consumer, &error));
	int64_t result = 99;
	assert(gi16_consumer_inspect(consumer, data, &result, &error) == (int32_t)UINT32_C(0x8001010e) && result == 0);
	assert(!gi16_consumer_destroy(&consumer, &error));
	return NULL;
}

extern int32_t gi16_run(void);

static void foreign_object_exports(void) {
	GError *error = NULL;
	Bridge16Facade *facade = bridge16_facade_new(7, &error);
	assert(facade && !error);
	Provider16Item *item = provider16_item_new(19, &error), *result = NULL;
	gint code = 0;
	guint before = item_destroyed;
	assert(bridge16_facade_try_inspect(facade, item, &code, &error) && code == 26 && !error);
	assert(bridge16_facade_try_relay(facade, item, &result, &error) && result == item && !error && item_destroyed == before);
	assert(provider16_item_try_code(result, &code, &error) && code == 19);
	g_object_unref(result);
	assert(item_destroyed == before + 1);
	assert(bridge16_facade_try_make(facade, 30, &result, &error) && result && !error);
	assert(provider16_item_try_code(result, &code, &error) && code == 37);
	g_object_unref(result);
	assert(item_destroyed == before + 2);
	assert(bridge16_facade_try_optional(facade, NULL, &result, &error) && !result && !error);
	item = provider16_item_new(23, &error);
	assert(bridge16_facade_try_optional(facade, item, &result, &error) && result == item && !error);
	g_object_unref(result);
	assert(item_destroyed == before + 3);
	item = provider16_item_new(29, &error);
	assert(!bridge16_facade_try_relay(facade, item, NULL, &error) && error);
	g_clear_error(&error);
	assert(item_destroyed == before + 4);
	item = (Provider16Item *)g_object_new(G_TYPE_OBJECT, NULL);
	assert(!bridge16_facade_try_relay(facade, item, &result, &error) && !result && error);
	g_clear_error(&error);
	g_object_run_dispose(G_OBJECT(facade));
	item = provider16_item_new(31, &error);
	assert(!bridge16_facade_try_relay(facade, item, &result, &error) && !result && error);
	g_clear_error(&error);
	assert(item_destroyed == before + 5);
	g_object_unref(facade);
}

int main(void) {
	assert(gi16_run() == 0);
	assert(destroyed == 3 && errors == 19 && record_retired == 3 && callback_environments == 1 && deliveries == 1 && byte_retirements == 4 && item_destroyed == 5);
	ForeignError error = {0, 0};
	assert(!go16_import_create(7, true, 2.5, &active_owner, &error));
	ImportedItem *item = NULL;
	assert(!gi16_item_create(77, &item, &error));
	ImportedItem *before = item;
	assert(go16_import_take(active_owner, &item, 0, (int32_t *)&item, &error) == (int32_t)UINT32_C(0x80070057) && item == before && item_destroyed == 5);
	gi16_item_release(item);
	assert(item_destroyed == 6);
	GThread *thread = g_thread_new("GObject imported context", wrong_context, active_owner);
	g_thread_join(thread);
	NativeConsumer *consumer = NULL;
	assert(!gi16_consumer_create(&consumer, &error));
	int64_t result = 0;
	assert(!gi16_consumer_inspect(consumer, active_owner, &result, &error) && result == 40 && !active_owner && destroyed == 4);
	assert(!gi16_consumer_destroy(&consumer, &error));
	foreign_object_exports();
	puts("PASS typed GObject imported methods, properties, BOOL32, references and GError retirement");
	return 0;
}

gboolean provider16_ledger_try_terminated(Provider16Ledger *self, gchar **result, GError **error) {
	(void)self;
	(void)error;
	*result = g_strdup("café");
	return TRUE;
}

gboolean provider16_ledger_try_terminated_empty(Provider16Ledger *self, gchar **result, GError **error) {
	(void)self;
	(void)error;
	*result = g_strdup("");
	return TRUE;
}

gboolean provider16_ledger_try_bounded(Provider16Ledger *self, GBytes *input, guint8 **output, gint *bound, gint mode, gint *result, GError **error) {
	return provider16_ledger_try_transform(self, input, output, bound, mode, result, error);
}

struct _Provider16Item {
	GObject parent_instance;
	gint code;
};
G_DEFINE_FINAL_TYPE(Provider16Item, provider16_item, G_TYPE_OBJECT)

static void provider16_item_finalize(GObject *object) {
	++item_destroyed;
	G_OBJECT_CLASS(provider16_item_parent_class)->finalize(object);
}

static void provider16_item_class_init(Provider16ItemClass *klass) {
	G_OBJECT_CLASS(klass)->finalize = provider16_item_finalize;
}

static void provider16_item_init(Provider16Item *self) {
	(void)self;
}

Provider16Item *provider16_item_new(gint code, GError **error) {
	(void)error;
	Provider16Item *result = g_object_new(provider16_item_get_type(), NULL);
	result->code = code;
	return result;
}

gboolean provider16_item_try_code(Provider16Item *self, gint *result, GError **error) {
	(void)error;
	*result = self->code;
	return TRUE;
}

gboolean provider16_ledger_try_make(Provider16Ledger *self, gint mode, Provider16Item **result, GError **error) {
	(void)self;
	if (mode == 2) {
		*result = NULL;
		return TRUE;
	}
	if (mode == 3) {
		*result = (Provider16Item *)g_object_new(G_TYPE_OBJECT, NULL);
		return TRUE;
	}
	*result = provider16_item_new(41, error);
	if (mode == 1) {
		g_set_error_literal(error, g_quark_from_static_string("astra-foreign-domain-16"), -1600, "provisional object failure");
		return FALSE;
	}
	return TRUE;
}

gboolean provider16_ledger_try_inspect(Provider16Ledger *self, Provider16Item *input, gint *result, GError **error) {
	(void)self;
	return provider16_item_try_code(input, result, error);
}

gboolean provider16_ledger_try_duplicate(Provider16Ledger *self, Provider16Item *input, Provider16Item **result, GError **error) {
	(void)self;
	(void)error;
	*result = g_object_ref(input);
	return TRUE;
}

gboolean provider16_ledger_try_lookup(Provider16Ledger *self, gboolean present, Provider16Item *input, Provider16Item **result, GError **error) {
	(void)self;
	(void)error;
	*result = present ? g_object_ref(input) : NULL;
	return TRUE;
}

gboolean provider16_ledger_try_take(Provider16Ledger *self, Provider16Item *input, gint mode, gint *result, GError **error) {
	(void)self;
	*result = input->code;
	g_object_unref(input);
	if (mode) {
		g_set_error_literal(error, g_quark_from_static_string("astra-foreign-domain-16"), -1600, "consumed owner failure");
		return FALSE;
	}
	return TRUE;
}

Provider16Sample *provider16_sample_copy(const Provider16Sample *value) {
	return g_memdup2(value, sizeof *value);
}

void provider16_sample_free(Provider16Sample *value) {
	++record_retired;
	g_free(value);
}
G_DEFINE_BOXED_TYPE(Provider16Sample, provider16_sample, provider16_sample_copy, provider16_sample_free)

Provider16Pair *provider16_pair_copy(const Provider16Pair *value) {
	return g_memdup2(value, sizeof *value);
}

void provider16_pair_free(Provider16Pair *value) {
	++record_retired;
	g_free(value);
}
G_DEFINE_BOXED_TYPE(Provider16Pair, provider16_pair, provider16_pair_copy, provider16_pair_free)

gboolean provider16_ledger_try_adjust(Provider16Ledger *self, Provider16Sample *input, gint mode, Provider16Sample **result, GError **error) {
	assert(input->astra_field_2_enabled == TRUE);
	if (mode == 2) {
		*result = NULL;
		return TRUE;
	}
	*result = provider16_sample_copy(input);
	(*result)->astra_field_0_count += self->seed;
	(*result)->astra_field_1_scale *= self->gain;
	(*result)->astra_field_2_enabled = FALSE;
	++(*result)->astra_field_4_stamp;
	(*result)->astra_field_5_weight += 0.5;
	if (mode) {
		g_set_error_literal(error, g_quark_from_static_string("astra-foreign-domain-16"), -1600, "provisional boxed result");
		return FALSE;
	}
	return TRUE;
}

gboolean provider16_ledger_try_pair(Provider16Ledger *self, Provider16Pair *input, Provider16Pair **result, GError **error) {
	(void)error;
	*result = provider16_pair_copy(input);
	(*result)->astra_field_0_first += self->gain;
	(*result)->astra_field_1_second += self->seed;
	return TRUE;
}
