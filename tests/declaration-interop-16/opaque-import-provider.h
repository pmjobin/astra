/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_OPAQUE_IMPORT_PROVIDER_H
#define ASTRA_OPAQUE_IMPORT_PROVIDER_H
#include <glib-object.h>
G_DECLARE_FINAL_TYPE(UnitProvider16, unit_provider16, UNIT, PROVIDER16, GObject)
UnitProvider16 *unit_provider16_new(gint, GError **);
gboolean unit_provider16_try_sum(UnitProvider16 *, gint, gint *, GError **);
#endif
