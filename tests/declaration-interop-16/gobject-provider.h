// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#pragma once
#include <glib-object.h>
G_DECLARE_FINAL_TYPE(Provider16Ledger, provider16_ledger, PROVIDER16, LEDGER, GObject)
Provider16Ledger *provider16_ledger_new(gint, gboolean, gdouble, GError **);
gboolean provider16_ledger_try_fold(Provider16Ledger *, gint64, guint, gfloat, guint64, gint64 *, GError **);
gboolean provider16_ledger_try_get_gain(Provider16Ledger *, gdouble *, GError **);
gboolean provider16_ledger_try_set_gain(Provider16Ledger *, gdouble, GError **);
gboolean provider16_ledger_try_choose(Provider16Ledger *, gboolean, gboolean *, GError **);
gboolean provider16_ledger_try_evaluate(Provider16Ledger *, gdouble, gdouble *, GError **);
gboolean provider16_ledger_try_refs(Provider16Ledger *, gint64, gdouble *, guint *, gboolean, gint64 *, GError **);

typedef gboolean (*Provider16FlagCallback)(gpointer, gboolean);
typedef void (*Provider16SinkCallback)(gpointer, gdouble);
gboolean provider16_ledger_try_visit(Provider16Ledger *, gboolean, Provider16FlagCallback, gpointer, gboolean *, GError **);
gboolean provider16_ledger_try_optional_visit(Provider16Ledger *, gboolean, Provider16FlagCallback, gpointer, gboolean *, GError **);
gboolean provider16_ledger_try_deliver(Provider16Ledger *, gdouble, Provider16SinkCallback, gpointer, GError **);

gboolean provider16_ledger_try_digest(Provider16Ledger *, GBytes *, gint *, GError **);
gboolean provider16_ledger_try_snapshot(Provider16Ledger *, GBytes *, gint, GBytes **, GError **);
gboolean provider16_ledger_try_text(Provider16Ledger *, gint, GBytes **, GError **);
gboolean provider16_ledger_try_measure(Provider16Ledger *, gchar *, GBytes *, gint *, GError **);
gboolean provider16_ledger_try_transform(Provider16Ledger *, GBytes *, guint8 **, gint *, gint, gint *, GError **);

gboolean provider16_ledger_try_terminated(Provider16Ledger *, gchar **, GError **);
gboolean provider16_ledger_try_terminated_empty(Provider16Ledger *, gchar **, GError **);

gboolean provider16_ledger_try_bounded(Provider16Ledger *, GBytes *, guint8 **, gint *, gint, gint *, GError **);

G_DECLARE_FINAL_TYPE(Provider16Item, provider16_item, PROVIDER16, ITEM, GObject)
Provider16Item *provider16_item_new(gint, GError **);
gboolean provider16_item_try_code(Provider16Item *, gint *, GError **);
gboolean provider16_ledger_try_make(Provider16Ledger *, gint, Provider16Item **, GError **);
gboolean provider16_ledger_try_inspect(Provider16Ledger *, Provider16Item *, gint *, GError **);
gboolean provider16_ledger_try_duplicate(Provider16Ledger *, Provider16Item *, Provider16Item **, GError **);
gboolean provider16_ledger_try_lookup(Provider16Ledger *, gboolean, Provider16Item *, Provider16Item **, GError **);
gboolean provider16_ledger_try_take(Provider16Ledger *, Provider16Item *, gint, gint *, GError **);

// The provider owns these independently declared boxed records. Field names are
// the declarations-v1 ordinal/member mapping, with GLib scalar storage.
typedef struct {
	gint astra_field_0_count;
	gdouble astra_field_1_scale;
	gboolean astra_field_2_enabled;
	guint astra_field_3_mask;
	guint64 astra_field_4_stamp;
	gfloat astra_field_5_weight;
} Provider16Sample;

typedef struct {
	gdouble astra_field_0_first;
	gint astra_field_1_second;
} Provider16Pair;

GType provider16_sample_get_type(void);
Provider16Sample *provider16_sample_copy(const Provider16Sample *);
void provider16_sample_free(Provider16Sample *);
GType provider16_pair_get_type(void);
Provider16Pair *provider16_pair_copy(const Provider16Pair *);
void provider16_pair_free(Provider16Pair *);
gboolean provider16_ledger_try_adjust(Provider16Ledger *, Provider16Sample *, gint, Provider16Sample **, GError **);
gboolean provider16_ledger_try_pair(Provider16Ledger *, Provider16Pair *, Provider16Pair **, GError **);
