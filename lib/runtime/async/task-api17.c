// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
/* Public protocol wrappers: one definition in the selected entry unit. */
#define RETURN_OPERATION(type, name, declaration, arguments) \
	type astra_async_##name declaration { lock_runtime(); type result = core_##name arguments; unlock_runtime(); return result; }
#define VOID_OPERATION(name, declaration, arguments) \
	void astra_async_##name declaration { lock_runtime(); core_##name arguments; unlock_runtime(); }

RETURN_OPERATION(AstraAsyncTask *, new, (size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent), (size, alignment, resume, destroy, parent))
RETURN_OPERATION(AstraAsyncTask *, new_allocated, (size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent, const AstraAsyncFrameAllocator *allocator, void *context), (size, alignment, resume, destroy, parent, allocator, context))
RETURN_OPERATION(AstraAsyncTask *, try_new_allocated, (size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent, const AstraAsyncFrameAllocator *allocator, void *context), (size, alignment, resume, destroy, parent, allocator, context))
void astra_async_require_provider(AstraAsyncTask *task, uint32_t provider) {
	lock_runtime();
	ASTRA_ASYNC_REQUIRE(task && !task->executor && task->phase == ASTRA_ASYNC_NEW && task->required_provider == UINT32_MAX && provider <= 2);
	task->required_provider = provider;
	unlock_runtime();
}
RETURN_OPERATION(void *, data, (AstraAsyncTask * task), (task))
RETURN_OPERATION(uint32_t, pc, (AstraAsyncTask * task), (task))
VOID_OPERATION(set_pc, (AstraAsyncTask * task, uint32_t pc), (task, pc))
RETURN_OPERATION(int, phase, (AstraAsyncTask * task), (task))
RETURN_OPERATION(int, cancel_requested, (AstraAsyncTask * task), (task))
RETURN_OPERATION(AstraAsyncExecutor *, executor, (AstraAsyncTask * task), (task))
RETURN_OPERATION(int, start, (AstraAsyncExecutor * executor, AstraAsyncTask *task, AstraAsyncTask *parent), (executor, task, parent))
RETURN_OPERATION(int, bridge_start, (AstraAsyncExecutor * target, AstraAsyncTask *child, AstraAsyncTask *parent), (target, child, parent))
RETURN_OPERATION(int, bridge_wait, (AstraAsyncTask * parent, AstraAsyncTask *child, AstraAsyncExecutor *target, int discard), (parent, child, target, discard))
VOID_OPERATION(cancel, (AstraAsyncTask * task), (task))
RETURN_OPERATION(int, cancel_scope, (AstraAsyncTask * task), (task))
RETURN_OPERATION(int, delay, (AstraAsyncTask * task, int64_t ticks), (task, ticks))
RETURN_OPERATION(int, wait, (AstraAsyncTask * parent, AstraAsyncTask *child, int discard), (parent, child, discard))
RETURN_OPERATION(AstraAsyncTask *, waited, (AstraAsyncTask * parent), (parent))
RETURN_OPERATION(int, release_wait, (AstraAsyncTask * parent, int transfer), (parent, transfer))
RETURN_OPERATION(void *, exception, (AstraAsyncTask * task), (task))
RETURN_OPERATION(void *, discarded_exception, (AstraAsyncTask * task, int discard), (task, discard))
VOID_OPERATION(complete, (AstraAsyncTask * task, int phase, void *exception), (task, phase, exception))
VOID_OPERATION(drop, (AstraAsyncTask * task), (task))
VOID_OPERATION(begin_shutdown, (AstraAsyncExecutor * executor), (executor))
int astra_async_request_shutdown(AstraAsyncExecutor *executor) {
	lock_runtime();
	ASTRA_ASYNC_REQUIRE(executor);
	if (executor->closed) {
		unlock_runtime();
		return 0;
	}
	/* Only publish metadata requests here. Provider cancellation runs on its
	 * owner; normal observation/close performs kernel drain and native joins. */
	executor->closing = 1;
	for (uint32_t i = 0; i < executor->capacity; ++i) {
		if (executor->registrations[i].task) core_cancel(executor->registrations[i].task);
	}
	notify(executor);
	unlock_runtime();
	return 1;
}
RETURN_OPERATION(int, shutdown_complete, (AstraAsyncExecutor * executor), (executor))
RETURN_OPERATION(int, finish_shutdown, (AstraAsyncExecutor * executor), (executor))
RETURN_OPERATION(int, observe_root, (AstraAsyncExecutor * executor, AstraAsyncTask *root, int transfer), (executor, root, transfer))
VOID_OPERATION(host_cancel, (AstraAsyncExecutor * executor, AstraAsyncTask *task), (executor, task))
RETURN_OPERATION(AstraAsyncToken, token, (AstraAsyncTask * task), (task))
RETURN_OPERATION(int, wake, (AstraAsyncExecutor * executor, AstraAsyncToken token), (executor, token))
RETURN_OPERATION(int, retain, (AstraAsyncTask * task, const void *backing), (task, backing))
RETURN_OPERATION(int, observe_release, (AstraAsyncExecutor * executor, AstraAsyncToken token), (executor, token))
RETURN_OPERATION(int, provider_read, (AstraAsyncExecutor * executor, AstraAsyncToken token), (executor, token))

RETURN_OPERATION(AstraAsyncExecutor *, provider_open, (uint32_t capacity, const AstraAsyncProvider *provider, void *state), (capacity, provider, state))
RETURN_OPERATION(void *, provider_state, (AstraAsyncExecutor * executor, const AstraAsyncProvider *provider), (executor, provider))
RETURN_OPERATION(int, provider_ready, (AstraAsyncExecutor * executor), (executor))
RETURN_OPERATION(int, provider_suspend, (AstraAsyncTask * task, const void *record), (task, record))
RETURN_OPERATION(int, provider_complete, (AstraAsyncExecutor * executor, AstraAsyncToken token, uint32_t pc, int error), (executor, token, pc, error))
RETURN_OPERATION(int, provider_result, (AstraAsyncTask * task, uint32_t pc), (task, pc))
int astra_async_concurrent_core(void) {
#ifdef ASTRA_ASYNC_PTHREADS
	return 1;
#else
	return 0;
#endif
}
void astra_async_provider_notify(AstraAsyncExecutor *executor, void (*notification)(void *), void *state) {
	lock_runtime();
	ASTRA_ASYNC_REQUIRE(executor && executor->provider && executor->associated == 0 && executor->retiring == 0 && (notification == NULL ? state == NULL : state != NULL));
	executor->notify = notification;
	executor->notify_state = state;
	unlock_runtime();
}
int astra_async_provider_take_cancel(AstraAsyncExecutor *executor, AstraAsyncToken *token) {
	lock_runtime();
	ASTRA_ASYNC_REQUIRE(executor && executor->provider && token);
	for (uint32_t i = 0; i < executor->capacity; ++i) {
		AstraAsyncRegistration *entry = &executor->registrations[i];
		if (entry->task && entry->cancel_pending) {
			entry->cancel_pending = 0;
			*token = entry->task->token;
			if (entry->task->pending_phase) publish(entry->task);
			unlock_runtime();
			return 1;
		}
	}
	unlock_runtime();
	return 0;
}
AstraAsyncExecutor *astra_async_virtual_open(uint32_t capacity) {
	lock_runtime();
	AstraAsyncExecutor *result = core_open(capacity);
	unlock_runtime();
	return result;
}

AstraAsyncExecutor *astra_async_open(uint32_t capacity) {
#ifdef ASTRA_ASYNC_LEGACY_WORKERS
	return worker_open(capacity);
#else
	return astra_async_virtual_open(capacity);
#endif
}
#ifdef ASTRA_ASYNC_PTHREADS
AstraAsyncExecutor *astra_async_threaded_open(uint32_t workers) {
	return worker_open(workers);
}
AstraAsyncExecutor *astra_async_worker_pool_open(int32_t workers) {
	return workers > 0 ? worker_open((uint32_t)workers) : NULL;
}
void astra_async_worker_pool_close(AstraAsyncExecutor *executor) {
	if (executor) {
		ASTRA_ASYNC_REQUIRE(executor->threaded);
		worker_close(executor);
	}
}
int astra_async_worker_pool_request_shutdown(AstraAsyncExecutor *executor) {
	ASTRA_ASYNC_REQUIRE(executor && executor->threaded);
	return astra_async_request_shutdown(executor);
}
#endif
int astra_async_run(AstraAsyncExecutor *executor, AstraAsyncTask *root, void **exception) {
#ifdef ASTRA_ASYNC_PTHREADS
	if (executor->threaded) return worker_run(executor, root, exception);
#endif
	lock_runtime();
	int result = core_run(executor, root, exception);
	unlock_runtime();
	return result;
}
uint32_t astra_async_pump(AstraAsyncExecutor *executor, uint32_t budget) {
#ifdef ASTRA_ASYNC_PTHREADS
	if (executor->threaded) return worker_pump(executor, budget);
#endif
	lock_runtime();
	uint32_t result = core_pump(executor, budget);
	unlock_runtime();
	return result;
}
void astra_async_close(AstraAsyncExecutor *executor) {
#ifdef ASTRA_ASYNC_PTHREADS
	if (executor->threaded) {
		worker_close(executor);
		return;
	}
#endif
	lock_runtime();
	core_close(executor);
	unlock_runtime();
}
int astra_async_advance(AstraAsyncExecutor *executor, uint64_t ticks) {
	if (executor->threaded) return 0;
	lock_runtime();
	int result = core_advance(executor, ticks);
	unlock_runtime();
	return result;
}
int astra_async_advance_next(AstraAsyncExecutor *executor) {
	if (executor->threaded) return 0;
	lock_runtime();
	int result = core_advance_next(executor);
	unlock_runtime();
	return result;
}
#ifdef ASTRA_ASYNC_TEST_PROTOCOL
VOID_OPERATION(test_generation, (AstraAsyncExecutor * executor, uint32_t slot, uint64_t generation), (executor, slot, generation))
#endif
#undef RETURN_OPERATION
#undef VOID_OPERATION
