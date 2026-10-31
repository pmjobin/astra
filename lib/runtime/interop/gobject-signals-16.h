/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_GOBJECT_SIGNALS_16_H
#define ASTRA_GOBJECT_SIGNALS_16_H
#include <glib-object.h>
#include <stdint.h>

/* Declaration-derived, synchronous, void signals. The generated marshaller
 * has an exact typed callback prototype; no arbitrary libffi signature exists.
 * A source weakly names an object. Each registration owns one object reference.
 * The native Closure owner keeps its carrier/environment until retire returns 1. */
void *astra_gobject16_signal_source(GObject *, const char *, const char *, GClosureMarshal, guint, const GType *);
int32_t astra_gobject16_signal_mode(void *);
void astra_gobject16_signal_source_free(void *);
void *astra_gobject16_signal_register(void (*)(void), void *, int32_t, const char *);
int32_t astra_gobject16_signal_revoke(void *);
int32_t astra_gobject16_signal_observe(void *);
int32_t astra_gobject16_signal_retire(void *);
/* Used only by generated typed marshallers while GObject pins their GClosure. */
int32_t astra_gobject16_signal_enter(void *);
void astra_gobject16_signal_leave(void *);
void (*astra_gobject16_signal_callback(void *))(void);
void *astra_gobject16_signal_context(void *);
int32_t astra_gobject16_signal_connections(void);
uint64_t astra_gobject16_signal_reentry_refusals(void);
#endif
