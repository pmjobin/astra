/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_RETAINED_H
#define ASTRA_RETAINED_H
#include <stdint.h>
/* Single thread, explicit dispatch only. Context is opaque native authority. */
typedef int32_t (*astra_retained_callback)(void *, int32_t);
/* Optional trusted single-threaded event provider. Version 1 open must not
 * dispatch before returning. stop prevents new callbacks; observe proves the
 * foreign callback has released its registration; close releases provider data.
 * Installing a provider does not change the ordinary mode-zero protocol. */
struct astra_retained_provider {
	uint32_t version;
	void *(*open)(int32_t, void *);
	int32_t (*stop)(void *);
	int32_t (*observe)(void *);
	int32_t (*close)(void *);
};
int32_t astra_retained_install_provider(const struct astra_retained_provider *);
void *astra_retained_register(astra_retained_callback, void *, int32_t);
int32_t astra_retained_dispatch(void *, int32_t);
int32_t astra_retained_revoke(void *);
int32_t astra_retained_observe(void *);
int32_t astra_retained_retire(void *);
#endif
