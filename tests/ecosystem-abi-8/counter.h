/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_TEST_COUNTER_H
#define ASTRA_TEST_COUNTER_H
#include "gobject.h"
GType ast_counter_get_type(void);
typedef struct _AstCounter AstCounter;
AstCounter *ast_counter_new(gint);
gint ast_counter_read(AstCounter *);
gint ast_counter_write(AstCounter *, gint);
const gchar *ast_counter_label(AstCounter *);
GObject *ast_counter_as_object(AstCounter *);
gint ast_counter_emit(AstCounter *, gint);
void *counter_new(int32_t);
int32_t counter_get(void *);
int32_t counter_set(void *, int32_t);
int32_t counter_label(void *, const uint8_t *, int32_t);
void *counter_snapshot(void *);
int32_t counter_finalized(void);
int32_t counter_disposed(void);
int32_t counter_emit(void *, int32_t);
#endif
