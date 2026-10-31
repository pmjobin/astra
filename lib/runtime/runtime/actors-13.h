// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#ifndef ASTRA_ACTORS_13_H
#define ASTRA_ACTORS_13_H
#include <stdint.h>
// Copied scalar transport preserves up to 64 exact bits; the compiler owns
// numeric/bool type reconstruction. It never transports a borrowed pointer.
typedef void (*AstraActorDispatch)(void *receiver, void *message, uint64_t scalar);
typedef void (*AstraActorDrop)(void *owner);
void *astra_actor_open(AstraActorDispatch dispatch, void *receiver,
                       AstraActorDrop drop_receiver, AstraActorDrop drop_message,
                       int32_t capacity, const char *name, int32_t name_length);
void *astra_actor_clone(void *sender);
int32_t astra_actor_send(void *sender, void *message, uint64_t scalar, AstraActorDrop drop);
int32_t astra_actor_cancel(void *sender);
int32_t astra_actor_shutdown(void *sender);
void astra_actor_release(void *sender);
int32_t astra_actor_cancelled(void);
#endif
