/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "retained.h"
#include <stddef.h>
#include <stdlib.h>
#include <limits.h>
/* A token is a monotonically unique opaque integer, never a context address.
 * No public operation dereferences the supplied token, including stale tokens.
 * The finite GNU LP64 domain refuses exhaustion rather than reusing identity. */
struct registration {
	uintptr_t identity;
	astra_retained_callback callback;
	void *context;
	unsigned active;
	unsigned stopped;
	unsigned observed;
	unsigned closing;
	const struct astra_retained_provider *provider;
	void *provider_data;
};
static struct registration *slots[64];
static uintptr_t next_identity = 1;
static const struct astra_retained_provider *event_provider;
int32_t astra_retained_install_provider(const struct astra_retained_provider *provider) {
	if (!provider || provider->version != 1 || !provider->open || !provider->stop || !provider->observe || !provider->close) return -1;
	if (event_provider && event_provider != provider) return -1;
	event_provider = provider;
	return 1;
}
static struct registration *lookup(void *token) {
	uintptr_t identity = (uintptr_t)token;
	for (size_t i = 0; i < 64; ++i)
		if (slots[i] && slots[i]->identity == identity) return slots[i];
	return NULL;
}
void *astra_retained_register(astra_retained_callback callback, void *context, int32_t mode) {
	if (!callback || !context || mode < 0 || (mode != 0 && !event_provider) || next_identity == UINTPTR_MAX) return NULL;
	size_t i = 0;
	while (i < 64 && slots[i])
		++i;
	if (i == 64) return NULL;
	struct registration *owner = calloc(1, sizeof *owner);
	if (!owner) return NULL;
	owner->identity = next_identity++;
	owner->callback = callback;
	owner->context = context;
	if (mode != 0) {
		owner->provider = event_provider;
		owner->provider_data = event_provider->open(mode, (void *)owner->identity);
		if (!owner->provider_data) {
			free(owner);
			return NULL;
		}
	}
	slots[i] = owner;
	return (void *)owner->identity;
}
int32_t astra_retained_dispatch(void *token, int32_t value) {
	struct registration *owner = lookup(token);
	if (!owner) return -3;
	if (owner->stopped || owner->active) return -2;
	owner->active = 1;
	int32_t result = owner->callback(owner->context, value);
	owner->active = 0;
	return result;
}
int32_t astra_retained_revoke(void *token) {
	struct registration *owner = lookup(token);
	if (!owner) return -3;
	if (owner->closing) return 0;
	owner->stopped = 1;
	if (owner->provider && owner->provider->stop(owner->provider_data) != 1) return 0;
	return 1;
}
int32_t astra_retained_observe(void *token) {
	struct registration *owner = lookup(token);
	if (!owner) return -3;
	if (!owner->stopped || owner->active || owner->closing) return 0;
	if (owner->provider && owner->provider->observe(owner->provider_data) != 1) return 0;
	owner->observed = 1;
	return 1;
}
int32_t astra_retained_retire(void *token) {
	struct registration *owner = lookup(token);
	if (!owner || owner->active || owner->closing) return 0;
	if (astra_retained_revoke(token) != 1 || astra_retained_observe(token) != 1 || !owner->observed) return 0;
	owner->closing = 1;
	if (owner->provider && owner->provider->close(owner->provider_data) != 1) {
		owner->closing = 0;
		return 0;
	}
	/* Retire publication first: late/stale calls can only return -3. */
	for (size_t i = 0; i < 64; ++i)
		if (slots[i] == owner) slots[i] = NULL;
	owner->callback = NULL;
	owner->context = NULL;
	free(owner);
	return 1;
}
