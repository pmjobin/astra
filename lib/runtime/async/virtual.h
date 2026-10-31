/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_ASYNC_VIRTUAL_H
#define ASTRA_ASYNC_VIRTUAL_H
#include <stddef.h>
#include <stdint.h>
#define ASTRA_ASYNC_TASK_ABI 17u

typedef struct AstraAsyncTask AstraAsyncTask;
typedef struct AstraAsyncExecutor AstraAsyncExecutor;
typedef void (*AstraAsyncResume)(AstraAsyncTask *task);
typedef void (*AstraAsyncDestroy)(AstraAsyncTask *task, int discard);
/* Optional frame backing. The compiler supplies the descriptor from its checked
 * allocator contract; default task clients introduce no allocator dependency.
 * Callbacks execute outside scheduler synchronization, cannot unwind, and must
 * keep descriptor/code/context valid through the final release. */
typedef struct AstraAsyncFrameAllocator {
	uint32_t abi, size, threading, reserved;
	void *(*allocate)(void *context, size_t size, size_t alignment);
	void (*release)(void *context, void *frame);
} AstraAsyncFrameAllocator;

/* Private compiler/runtime protocol, never a source exception or Result ABI. */
enum AstraAsyncPhase { ASTRA_ASYNC_NEW,
	                   ASTRA_ASYNC_READY,
	                   ASTRA_ASYNC_RUNNING,
	                   ASTRA_ASYNC_WAITING,
	                   ASTRA_ASYNC_DRAINING,
	                   ASTRA_ASYNC_SUCCESS,
	                   ASTRA_ASYNC_EXCEPTION,
	                   ASTRA_ASYNC_CANCELLED };
enum AstraAsyncAdmission { ASTRA_ASYNC_ADMITTED,
	                       ASTRA_ASYNC_CLOSED,
	                       ASTRA_ASYNC_CAPACITY,
	                       ASTRA_ASYNC_ASSOCIATION,
	                       ASTRA_ASYNC_ROOT,
	                       ASTRA_ASYNC_CANCELLED_COLD };
typedef struct AstraAsyncToken {
	uint32_t slot;
	uint64_t generation;
	uint64_t executor;
} AstraAsyncToken;

AstraAsyncExecutor *astra_async_open(uint32_t capacity);
/* Distinct constructors compose behind the one versioned task protocol. */
AstraAsyncExecutor *astra_async_virtual_open(uint32_t capacity);
AstraAsyncExecutor *astra_async_threaded_open(uint32_t workers);
AstraAsyncExecutor *astra_async_worker_pool_open(int32_t workers);
void astra_async_worker_pool_close(AstraAsyncExecutor *executor);
int astra_async_worker_pool_request_shutdown(AstraAsyncExecutor *executor);
AstraAsyncTask *astra_async_new(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent);
AstraAsyncTask *astra_async_new_allocated(size_t size, size_t alignment,
                                          AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent,
                                          const AstraAsyncFrameAllocator *allocator, void *context);
/* Refusal publishes no task/parent link and consumes no caller capture. A
 * successful caller must initialize captures before admitting the cold task. */
AstraAsyncTask *astra_async_try_new_allocated(size_t size, size_t alignment,
                                              AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent,
                                              const AstraAsyncFrameAllocator *allocator, void *context);
void astra_async_require_provider(AstraAsyncTask *task, uint32_t provider);
void *astra_async_data(AstraAsyncTask *task);
uint32_t astra_async_pc(AstraAsyncTask *task);
void astra_async_set_pc(AstraAsyncTask *task, uint32_t pc);
int astra_async_phase(AstraAsyncTask *task);
int astra_async_cancel_requested(AstraAsyncTask *task);
int astra_async_start(AstraAsyncExecutor *executor, AstraAsyncTask *task, AstraAsyncTask *parent);
int astra_async_bridge_start(AstraAsyncExecutor *target, AstraAsyncTask *child, AstraAsyncTask *parent);
int astra_async_bridge_wait(AstraAsyncTask *parent, AstraAsyncTask *child, AstraAsyncExecutor *target, int discard);
void astra_async_cancel(AstraAsyncTask *task);
int astra_async_cancel_scope(AstraAsyncTask *task);
int astra_async_delay(AstraAsyncTask *task, int64_t ticks);
int astra_async_wait(AstraAsyncTask *parent, AstraAsyncTask *child, int discard);
AstraAsyncTask *astra_async_waited(AstraAsyncTask *parent);
int astra_async_release_wait(AstraAsyncTask *parent, int transfer);
void *astra_async_exception(AstraAsyncTask *task);
void *astra_async_discarded_exception(AstraAsyncTask *task, int discard);
void astra_async_complete(AstraAsyncTask *task, int phase, void *exception);
void astra_async_drop(AstraAsyncTask *task);
uint32_t astra_async_pump(AstraAsyncExecutor *executor, uint32_t budget);
int astra_async_advance(AstraAsyncExecutor *executor, uint64_t ticks);
int astra_async_advance_next(AstraAsyncExecutor *executor);
void astra_async_begin_shutdown(AstraAsyncExecutor *executor);
int astra_async_request_shutdown(AstraAsyncExecutor *executor);
int astra_async_shutdown_complete(AstraAsyncExecutor *executor);
int astra_async_finish_shutdown(AstraAsyncExecutor *executor);
int astra_async_observe_root(AstraAsyncExecutor *executor, AstraAsyncTask *root, int transfer);
void astra_async_close(AstraAsyncExecutor *executor);
int astra_async_run(AstraAsyncExecutor *executor, AstraAsyncTask *root, void **exception);
void astra_async_host_cancel(AstraAsyncExecutor *executor, AstraAsyncTask *task);
AstraAsyncExecutor *astra_async_executor(AstraAsyncTask *task);

/* Native test-provider controls retain a real backing pointer. They are not I/O. */
AstraAsyncToken astra_async_token(AstraAsyncTask *task);
int astra_async_wake(AstraAsyncExecutor *executor, AstraAsyncToken token);
int astra_async_retain(AstraAsyncTask *task, const void *backing);
int astra_async_observe_release(AstraAsyncExecutor *executor, AstraAsyncToken token);
int astra_async_provider_read(AstraAsyncExecutor *executor, AstraAsyncToken token);
#ifdef ASTRA_ASYNC_TEST_PROTOCOL
void astra_async_test_generation(AstraAsyncExecutor *executor, uint32_t slot, uint64_t generation);
#endif
#endif
