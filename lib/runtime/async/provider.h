/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_ASYNC_PROVIDER_H
#define ASTRA_ASYNC_PROVIDER_H
#include "virtual.h"

/* Private finite provider seam. Ownership and task dispatch stay in the core. */
typedef struct AstraAsyncProvider {
	void (*service)(AstraAsyncExecutor *executor, int wait);
	void (*cancel)(AstraAsyncExecutor *executor, AstraAsyncToken token);
	void (*close)(AstraAsyncExecutor *executor);
} AstraAsyncProvider;

AstraAsyncExecutor *astra_async_provider_open(uint32_t capacity, const AstraAsyncProvider *provider, void *state);
void *astra_async_provider_state(AstraAsyncExecutor *executor, const AstraAsyncProvider *provider);
int astra_async_provider_ready(AstraAsyncExecutor *executor);
int astra_async_provider_suspend(AstraAsyncTask *task, const void *record);
int astra_async_provider_complete(AstraAsyncExecutor *executor, AstraAsyncToken token, uint32_t pc, int error);
int astra_async_provider_result(AstraAsyncTask *task, uint32_t pc);
/* An internal nonblocking wake publication. The provider owns its notification
 * fd/state until close; only its owner services returned cancel tokens. */
int astra_async_concurrent_core(void);
void astra_async_provider_notify(AstraAsyncExecutor *, void (*notify)(void *), void *state);
int astra_async_provider_take_cancel(AstraAsyncExecutor *, AstraAsyncToken *);
#endif
