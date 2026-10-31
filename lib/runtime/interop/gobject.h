/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_GOBJECT_H
#define ASTRA_GOBJECT_H
#include <glib-object.h>
#include <stdint.h>

/* Optional, single-threaded foreign boundary. Tokens are never native Classes
 * or GObject addresses. Only trusted C adapters may admit actual GObjects.
 * take consumes one valid transfer-full reference even if admission fails.
 * peek borrows only until the next adapter operation; never cache its result. */
void *astra_gobject_take(GObject *, GType);
GObject *astra_gobject_peek(void *, GType);
void *astra_gobject_ref(void *);
void astra_gobject_unref(void *);
int32_t astra_gobject_release_checked(void *);
int32_t astra_gobject_identity(void *);
int32_t astra_gobject_same(void *, void *);
void *astra_gobject_weak(void *);
void *astra_gobject_upgrade(void *);
void astra_gobject_weak_free(void *);
int32_t astra_gobject_set_int(void *, const char *, int32_t);
int32_t astra_gobject_get_int(void *, const char *, int32_t *);
int32_t astra_gobject_set_utf8(void *, const char *, const uint8_t *, int32_t);
void *astra_gobject_copy_utf8(void *, const char *);
void *astra_gobject_copy_text(const char *);
int32_t astra_gobject_text_length(void *);
int32_t astra_gobject_text_byte(void *, int32_t);
void astra_gobject_text_free(void *);
int32_t astra_gobject_live_handles(void);
#endif
