/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_GOBJECT_SIGNALS_H
#define ASTRA_GOBJECT_SIGNALS_H
#include "gobject.h"
/* A source token weakly names an actual runtime-checked int(int) signal.
 * A successful retained registration takes its own strong object reference. */
void *astra_gobject_signal_source(void *, const uint8_t *, int32_t);
int32_t astra_gobject_signal_mode(void *);
void astra_gobject_signal_source_free(void *);
int32_t astra_gobject_signal_connections(void);
#endif
