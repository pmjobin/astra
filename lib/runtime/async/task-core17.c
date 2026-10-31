/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "virtual.h"
#include "provider.h"
#define ASTRA_ASYNC_REQUIRE(condition) do { if (!(condition)) { abort(); } } while (0)
#include <limits.h>
#include <stdlib.h>

/* One canonical layout and ownership engine for all hosted backends.
 * Entry units include this once; no provider recompiles a renamed public core.
 * All core_ operations below require the metadata lock. */
static void lock_runtime(void);
static void unlock_runtime(void);
static void retire_begin(AstraAsyncTask *task);
static void retire_end(AstraAsyncTask *task);
static int wait_publication(AstraAsyncExecutor *executor);
static AstraAsyncExecutor *core_open(uint32_t capacity);
static AstraAsyncTask *core_new(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent);
static AstraAsyncTask *core_new_allocated(size_t, size_t, AstraAsyncResume, AstraAsyncDestroy, AstraAsyncTask *, const AstraAsyncFrameAllocator *, void *);
static AstraAsyncTask *core_try_new_allocated(size_t, size_t, AstraAsyncResume, AstraAsyncDestroy, AstraAsyncTask *, const AstraAsyncFrameAllocator *, void *);
static void *core_data(AstraAsyncTask *task);
static uint32_t core_pc(AstraAsyncTask *task);
static void core_set_pc(AstraAsyncTask *task, uint32_t pc);
static int core_phase(AstraAsyncTask *task);
static int core_cancel_requested(AstraAsyncTask *task);
static int core_start(AstraAsyncExecutor *executor, AstraAsyncTask *task, AstraAsyncTask *parent);
static int core_enroll(AstraAsyncExecutor *, AstraAsyncTask *, AstraAsyncTask *, int);
static int core_bridge_start(AstraAsyncExecutor *, AstraAsyncTask *, AstraAsyncTask *);
static int core_bridge_wait(AstraAsyncTask *, AstraAsyncTask *, AstraAsyncExecutor *, int);
static void core_cancel(AstraAsyncTask *task);
static int core_cancel_scope(AstraAsyncTask *task);
static int core_delay(AstraAsyncTask *task, int64_t ticks);
static int core_wait(AstraAsyncTask *parent, AstraAsyncTask *child, int discard);
static int core_wait_impl(AstraAsyncTask *, AstraAsyncTask *, int, int);
static AstraAsyncTask *core_waited(AstraAsyncTask *parent);
static int core_release_wait(AstraAsyncTask *parent, int transfer);
static void *core_exception(AstraAsyncTask *task);
static void *core_discarded_exception(AstraAsyncTask *task, int discard);
static void core_complete(AstraAsyncTask *task, int phase, void *exception);
static void core_drop(AstraAsyncTask *task);
static uint32_t core_pump(AstraAsyncExecutor *executor, uint32_t budget);
static int core_advance(AstraAsyncExecutor *executor, uint64_t ticks);
static int core_advance_next(AstraAsyncExecutor *executor);
static void core_begin_shutdown(AstraAsyncExecutor *executor);
static int core_shutdown_complete(AstraAsyncExecutor *executor);
static int core_finish_shutdown(AstraAsyncExecutor *executor);
static int core_observe_root(AstraAsyncExecutor *executor, AstraAsyncTask *root, int transfer);
static void core_close(AstraAsyncExecutor *executor);
static int core_run(AstraAsyncExecutor *executor, AstraAsyncTask *root, void **exception);
static void core_host_cancel(AstraAsyncExecutor *executor, AstraAsyncTask *task);
static AstraAsyncExecutor *core_executor(AstraAsyncTask *task);
static AstraAsyncToken core_token(AstraAsyncTask *task);
static int core_wake(AstraAsyncExecutor *executor, AstraAsyncToken token);
static int core_retain(AstraAsyncTask *task, const void *backing);
static int core_observe_release(AstraAsyncExecutor *executor, AstraAsyncToken token);
static int core_provider_read(AstraAsyncExecutor *executor, AstraAsyncToken token);
static AstraAsyncExecutor *core_provider_open(uint32_t capacity, const AstraAsyncProvider *provider, void *state);
static void *core_provider_state(AstraAsyncExecutor *executor, const AstraAsyncProvider *provider);
static int core_provider_ready(AstraAsyncExecutor *executor);
static int core_provider_suspend(AstraAsyncTask *task, const void *record);
static int core_provider_complete(AstraAsyncExecutor *executor, AstraAsyncToken token, uint32_t pc, int error);
static int core_provider_result(AstraAsyncTask *task, uint32_t pc);
#ifdef ASTRA_ASYNC_TEST_PROTOCOL
static void core_test_generation(AstraAsyncExecutor *, uint32_t, uint64_t);
#endif

typedef struct AstraAsyncRegistration {
	AstraAsyncTask *task;
	uint64_t generation;
	uint64_t deadline;
	const void *backing;
	uint32_t retained;
	uint32_t external_pc;
	int external_error;
	unsigned external : 1;
	unsigned external_result : 1;
	unsigned ready : 1;
	unsigned timer : 1;
	unsigned exhausted : 1;
	unsigned cancel_pending : 1;
} AstraAsyncRegistration;

struct AstraAsyncExecutor {
	const AstraAsyncProvider *provider;
	void *provider_state;
	void (*notify)(void *);
	void *notify_state;
	AstraAsyncRegistration *registrations;
	AstraAsyncTask *root;
	uint64_t ticks;
	uint64_t identity;
	uint32_t capacity;
	uint32_t cursor;
	uint32_t associated;
	uint32_t retiring;
	uint32_t bridges;
	uint32_t bridge_peak;
	unsigned threaded : 1;
	unsigned pumping : 1;
	unsigned closing : 1;
	unsigned closed : 1;
	unsigned root_admitted : 1;
	unsigned root_observed : 1;
};

struct AstraAsyncTask {
	void *data;
	void *exception;
	AstraAsyncResume resume;
	AstraAsyncDestroy destroy;
	void (*frame_release)(void *, void *);
	void *frame_context;
	uint32_t frame_threading;
	uint32_t required_provider;
	AstraAsyncExecutor *executor;
	AstraAsyncExecutor *bridge_source;
	AstraAsyncToken bridge_parent;
	AstraAsyncTask *parent;
	AstraAsyncTask *first_child;
	AstraAsyncTask *next_child;
	AstraAsyncTask *waiting;
	AstraAsyncTask *cancel_cursor;
	AstraAsyncToken token;
	uint32_t pc;
	int phase;
	int pending_phase;
	unsigned cancellation : 1;
	unsigned observation_acquired : 1;
	unsigned discard_wait : 1;
	unsigned threaded_busy : 1;
	unsigned threaded_migrated : 1;
	uint32_t threaded_last_worker;
};

static uint64_t next_executor = 1;

static void retire_begin(AstraAsyncTask *task) {
	if (task->executor) ++task->executor->retiring;
	unlock_runtime();
}
static void retire_end(AstraAsyncTask *task) {
	lock_runtime();
	if (task->executor) {
		ASTRA_ASYNC_REQUIRE(task->executor->retiring != 0);
		--task->executor->retiring;
	}
}

static int terminal(const AstraAsyncTask *task) {
	return task->phase >= ASTRA_ASYNC_SUCCESS;
}
static AstraAsyncRegistration *registration(AstraAsyncTask *task) {
	ASTRA_ASYNC_REQUIRE(task->executor != NULL && task->token.slot < task->executor->capacity);
	AstraAsyncRegistration *entry = &task->executor->registrations[task->token.slot];
	ASTRA_ASYNC_REQUIRE(entry->task == task && entry->generation == task->token.generation);
	return entry;
}
static int quiescent(AstraAsyncTask *task) {
	if (task->threaded_busy) {
		return 0;
	}
	if (task->executor == NULL) {
		return 1;
	}
	AstraAsyncRegistration *entry = registration(task);
	return !entry->ready && !entry->timer && !entry->external && !entry->cancel_pending && entry->retained == 0;
}

static void unlink_parent(AstraAsyncTask *task) {
	if (task->parent == NULL) {
		return;
	}
	AstraAsyncTask **current = &task->parent->first_child;
	while (*current != task) {
		ASTRA_ASYNC_REQUIRE(*current != NULL);
		current = &(*current)->next_child;
	}
	*current = task->next_child;
	if (task->bridge_source) {
		ASTRA_ASYNC_REQUIRE(task->parent->executor == task->bridge_source && task->bridge_source->bridges != 0);
		--task->bridge_source->bridges;
		task->bridge_source = NULL;
	}
	if (task->parent->cancel_cursor == task) {
		task->parent->cancel_cursor = task->next_child;
	}
	task->parent = NULL;
	task->next_child = NULL;
}

static void notify(AstraAsyncExecutor *executor) {
	if (executor->notify) executor->notify(executor->notify_state);
}
static void schedule(AstraAsyncTask *task) {
	if (task->executor != NULL && !terminal(task)) {
		registration(task)->ready = 1;
		notify(task->executor);
	}
}

static void notify_parent(AstraAsyncTask *task) {
	if (task->parent != NULL && (task->parent->waiting == task || task->parent->cancellation)) {
		schedule(task->parent);
	}
}

static void publish(AstraAsyncTask *task) {
	if (task->pending_phase == 0 || !quiescent(task) || task->first_child != NULL) {
		return;
	}
	/* No operation can rewrite a published outcome. */
	ASTRA_ASYNC_REQUIRE(!terminal(task));
	task->phase = task->cancellation ? ASTRA_ASYNC_CANCELLED : task->pending_phase;
	task->pending_phase = 0;
	notify_parent(task);
}

static void retire(AstraAsyncTask *task, int transfer) {
	ASTRA_ASYNC_REQUIRE(task != NULL && task->first_child == NULL && task->waiting == NULL);
	ASTRA_ASYNC_REQUIRE((task->phase == ASTRA_ASYNC_NEW || terminal(task)) && quiescent(task));
	unlink_parent(task);
	if (task->executor != NULL) {
		AstraAsyncRegistration *entry = registration(task);
		entry->task = NULL;
		entry->backing = NULL;
		ASTRA_ASYNC_REQUIRE(task->executor->associated != 0);
		task->executor->associated--;
	}
	retire_begin(task);
	task->destroy(task, !transfer);
	if (task->frame_release)
		task->frame_release(task->frame_context, task->data);
	else
		free(task->data);
	retire_end(task);
	free(task);
}

static AstraAsyncExecutor *core_open(uint32_t capacity) {
	if (capacity == 0 || capacity > 1048576 || next_executor == UINT64_MAX) {
		return NULL;
	}
	AstraAsyncExecutor *executor = calloc(1, sizeof(*executor));
	if (executor == NULL) {
#ifdef ASTRA_ASYNC_PTHREADS
		return NULL;
#else
		abort();
#endif
	}
	executor->registrations = calloc(capacity, sizeof(*executor->registrations));
	if (executor->registrations == NULL) {
#ifdef ASTRA_ASYNC_PTHREADS
		free(executor);
		return NULL;
#else
		abort();
#endif
	}
	executor->capacity = capacity;
	executor->identity = next_executor++;
	return executor;
}

static AstraAsyncTask *core_new(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent) {
	return core_new_allocated(size, alignment, resume, destroy, parent, NULL, NULL);
}
static AstraAsyncTask *core_new_allocated(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent, const AstraAsyncFrameAllocator *allocator, void *context) {
	AstraAsyncTask *task = core_try_new_allocated(size, alignment, resume, destroy, parent, allocator, context);
	ASTRA_ASYNC_REQUIRE(task != NULL);
	return task;
}
static AstraAsyncTask *core_try_new_allocated(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent, const AstraAsyncFrameAllocator *allocator, void *context) {
	if (!resume || !destroy || !alignment || (alignment & (alignment - 1)) != 0) return NULL;
	if (allocator == NULL ? context != NULL : context == NULL || allocator->abi != ASTRA_ASYNC_TASK_ABI || allocator->size != sizeof(*allocator) || allocator->threading > 2 || allocator->reserved != 0 || !allocator->allocate || !allocator->release) return NULL;
	if (alignment < sizeof(void *)) {
		alignment = sizeof(void *);
	}
	if (size == 0) {
		size = alignment;
	}
	if (size > SIZE_MAX - alignment + 1) return NULL;
	size = (size + alignment - 1) & ~(alignment - 1);
	/* The calling frame remains pinned while allocation runs. Publication to
	 * its parent happens only after backing admission and reacquiring the lock. */
	unlock_runtime();
	AstraAsyncTask *task = calloc(1, sizeof(*task));
	if (task == NULL) {
		lock_runtime();
		return NULL;
	}
	task->data = allocator ? allocator->allocate(context, size, alignment) : aligned_alloc(alignment, size);
	if (task->data == NULL) {
		free(task);
		lock_runtime();
		return NULL;
	}
	ASTRA_ASYNC_REQUIRE(((uintptr_t)task->data & (alignment - 1)) == 0);
	task->frame_release = allocator ? allocator->release : NULL;
	task->frame_context = context;
	task->frame_threading = allocator ? allocator->threading : 2;
	task->required_provider = UINT32_MAX;
	lock_runtime();
	task->resume = resume;
	task->destroy = destroy;
	task->phase = ASTRA_ASYNC_NEW;
	task->parent = parent;
	if (parent != NULL) {
		ASTRA_ASYNC_REQUIRE(!terminal(parent));
		task->next_child = parent->first_child;
		parent->first_child = task;
	}
	return task;
}

static void *core_data(AstraAsyncTask *task) {
	return task->data;
}
static uint32_t core_pc(AstraAsyncTask *task) {
	return task->pc;
}
static void core_set_pc(AstraAsyncTask *task, uint32_t pc) {
	ASTRA_ASYNC_REQUIRE(!terminal(task));
	task->pc = pc;
}
static int core_phase(AstraAsyncTask *task) {
	return task->phase;
}
static int core_cancel_requested(AstraAsyncTask *task) {
	return task->cancellation;
}
static AstraAsyncExecutor *core_executor(AstraAsyncTask *task) {
	return task->executor;
}
static void *core_exception(AstraAsyncTask *task) {
	ASTRA_ASYNC_REQUIRE(terminal(task));
	return task->exception;
}
static void *core_discarded_exception(AstraAsyncTask *task, int discard) {
	return !discard && task->phase == ASTRA_ASYNC_EXCEPTION ? NULL : task->exception;
}

static int core_start(AstraAsyncExecutor *executor, AstraAsyncTask *task, AstraAsyncTask *parent) {
	return core_enroll(executor, task, parent, 0);
}
static int core_enroll(AstraAsyncExecutor *executor, AstraAsyncTask *task, AstraAsyncTask *parent, int bridge) {
	ASTRA_ASYNC_REQUIRE(executor != NULL && task != NULL);
	if (executor->closing || executor->closed) {
		return ASTRA_ASYNC_CLOSED;
	}
	if (executor->threaded && task->frame_threading != 2) {
		return ASTRA_ASYNC_ASSOCIATION;
	}
	if (task->required_provider != UINT32_MAX && task->required_provider != (executor->threaded ? 2u : executor->provider ? 1u
	                                                                                                                      : 0u)) {
		return ASTRA_ASYNC_ASSOCIATION;
	}
	if (task->executor != NULL) {
		return task->executor == executor && task->parent == parent ? ASTRA_ASYNC_ADMITTED : ASTRA_ASYNC_ASSOCIATION;
	}
	if (task->phase == ASTRA_ASYNC_CANCELLED) {
		return ASTRA_ASYNC_CANCELLED_COLD;
	}
	if (task->phase != ASTRA_ASYNC_NEW || task->parent != parent) {
		return ASTRA_ASYNC_ASSOCIATION;
	}
	if (parent == NULL && executor->root_admitted) {
		return ASTRA_ASYNC_ROOT;
	}
	if (parent != NULL && parent->executor != executor && !bridge) {
		return ASTRA_ASYNC_ASSOCIATION;
	}
	uint32_t slot;
	for (slot = 0; slot < executor->capacity; slot++) {
		AstraAsyncRegistration *candidate = &executor->registrations[slot];
		if (candidate->generation == UINT64_MAX) {
			candidate->exhausted = 1;
		}
		if (candidate->task == NULL && !candidate->exhausted) {
			break;
		}
	}
	if (slot == executor->capacity) {
		return ASTRA_ASYNC_CAPACITY;
	}
	AstraAsyncRegistration *entry = &executor->registrations[slot];
	entry->external_result = 0;
	entry->generation++;
	entry->task = task;
	entry->ready = 1;
	task->token = (AstraAsyncToken){slot, entry->generation, executor->identity};
	task->executor = executor;
	task->phase = ASTRA_ASYNC_READY;
	executor->associated++;
	if (bridge) {
		task->bridge_source = parent->executor;
		task->bridge_parent = parent->token;
		++parent->executor->bridges;
		if (parent->executor->bridges > parent->executor->bridge_peak) parent->executor->bridge_peak = parent->executor->bridges;
	}
	if (parent == NULL) {
		executor->root = task;
		executor->root_admitted = 1;
	}
	notify(executor);
	return ASTRA_ASYNC_ADMITTED;
}

static int same_token(AstraAsyncToken a, AstraAsyncToken b) {
	return a.slot == b.slot && a.generation == b.generation && a.executor == b.executor;
}
static int core_bridge_start(AstraAsyncExecutor *target, AstraAsyncTask *child, AstraAsyncTask *parent) {
	ASTRA_ASYNC_REQUIRE(target && child && parent && parent->executor && parent->phase == ASTRA_ASYNC_RUNNING && child->parent == parent);
	if (!target->threaded || parent->executor->threaded || parent->executor == target || parent->cancellation || parent->executor->closing) return ASTRA_ASYNC_ASSOCIATION;
	if (child->executor) return child->executor == target && child->bridge_source == parent->executor && same_token(child->bridge_parent, parent->token) ? ASTRA_ASYNC_ADMITTED : ASTRA_ASYNC_ASSOCIATION;
	if (parent->executor->bridges == parent->executor->capacity) return ASTRA_ASYNC_CAPACITY;
	return core_enroll(target, child, parent, 1);
}

static void core_cancel(AstraAsyncTask *task) {
	ASTRA_ASYNC_REQUIRE(task != NULL);
	if (terminal(task)) {
		return;
	}
	task->cancellation = 1;
	if (task->executor == NULL) {
		task->phase = ASTRA_ASYNC_CANCELLED;
		return;
	}
	AstraAsyncRegistration *entry = registration(task);
	if (task->executor->provider != NULL) {
		if (task->executor->notify) {
			entry->cancel_pending = 1;
			notify(task->executor);
		} else {
			unlock_runtime();
			task->executor->provider->cancel(task->executor, task->token);
			lock_runtime();
		}
	}
	entry->timer = 0;
	entry->ready = 1;
	notify(task->executor);
}

static int core_cancel_scope(AstraAsyncTask *task) {
	ASTRA_ASYNC_REQUIRE(task->cancellation && !terminal(task));
	int pending = 0;
	AstraAsyncTask *child = task->cancel_cursor != NULL ? task->cancel_cursor : task->first_child;
	unsigned serviced = 0;
	while (child != NULL && serviced++ < 16) {
		AstraAsyncTask *next = child->next_child;
		core_cancel(child);
		if (terminal(child) && quiescent(child)) {
			if (task->waiting == child) {
				task->waiting = NULL;
			}
			retire(child, 0);
		} else {
			pending = 1;
		}
		child = next;
	}
	task->cancel_cursor = child;
	if (child != NULL) {
		schedule(task);
	}
	if (pending || task->first_child != NULL || (task->executor != NULL && registration(task)->retained != 0)) {
		task->phase = ASTRA_ASYNC_DRAINING;
		return 0;
	}
	return 1;
}

static int core_delay(AstraAsyncTask *task, int64_t ticks) {
	ASTRA_ASYNC_REQUIRE(task->executor != NULL && task->executor->provider == NULL);
	ASTRA_ASYNC_REQUIRE(task->executor != NULL && task->phase == ASTRA_ASYNC_RUNNING && !registration(task)->timer);
	if (ticks < 0 || (uint64_t)ticks > UINT64_MAX - task->executor->ticks) {
		return 0;
	}
	AstraAsyncRegistration *entry = registration(task);
	entry->deadline = task->executor->ticks + ticks;
	entry->timer = ticks != 0;
	entry->ready = ticks == 0;
	task->phase = ASTRA_ASYNC_WAITING;
	return 1;
}

static int core_wait(AstraAsyncTask *parent, AstraAsyncTask *child, int discard) {
	return core_wait_impl(parent, child, discard, 0);
}
static int core_wait_impl(AstraAsyncTask *parent, AstraAsyncTask *child, int discard, int bridge) {
	ASTRA_ASYNC_REQUIRE(parent != NULL && child != NULL && parent->executor != NULL && parent->waiting == NULL && child->parent == parent && !child->observation_acquired);
	child->observation_acquired = 1;
	if (discard) {
		core_cancel(child);
	}
	if (child->executor == NULL && !terminal(child)) {
		int result = core_start(parent->executor, child, parent);
		if (result != ASTRA_ASYNC_ADMITTED) {
			retire(child, 0);
			return result;
		}
	}
	ASTRA_ASYNC_REQUIRE(child->executor == NULL || child->executor == parent->executor || (bridge && child->bridge_source == parent->executor && same_token(child->bridge_parent, parent->token)));
	parent->waiting = child;
	parent->discard_wait = discard != 0;
	parent->phase = ASTRA_ASYNC_WAITING;
	if (terminal(child) && quiescent(child)) {
		schedule(parent);
	}
	return ASTRA_ASYNC_ADMITTED;
}

static int core_bridge_wait(AstraAsyncTask *parent, AstraAsyncTask *child, AstraAsyncExecutor *target, int discard) {
	ASTRA_ASYNC_REQUIRE(parent && child && target && target->threaded && parent->executor && !parent->executor->threaded && child->parent == parent);
	if (!child->executor && discard) return core_wait(parent, child, 1);
	if (!child->executor) {
		int result = core_bridge_start(target, child, parent);
		if (result != ASTRA_ASYNC_ADMITTED) {
			retire(child, 0);
			return result;
		}
	}
	ASTRA_ASYNC_REQUIRE(child->executor == target && child->bridge_source == parent->executor && same_token(child->bridge_parent, parent->token));
	return core_wait_impl(parent, child, discard, 1);
}

static AstraAsyncTask *core_waited(AstraAsyncTask *parent) {
	ASTRA_ASYNC_REQUIRE(parent->waiting != NULL && terminal(parent->waiting) && quiescent(parent->waiting));
	return parent->waiting;
}
static int core_release_wait(AstraAsyncTask *parent, int transfer) {
	AstraAsyncTask *child = core_waited(parent);
	int phase = child->phase;
	parent->waiting = NULL;
	retire(child, transfer && !parent->discard_wait);
	if (!parent->discard_wait && phase == ASTRA_ASYNC_CANCELLED) {
		core_cancel(parent);
	}
	parent->discard_wait = 0;
	return phase;
}

static void core_complete(AstraAsyncTask *task, int phase, void *exception) {
	ASTRA_ASYNC_REQUIRE(!terminal(task) && task->pending_phase == 0 && phase >= ASTRA_ASYNC_SUCCESS && phase <= ASTRA_ASYNC_CANCELLED);
	ASTRA_ASYNC_REQUIRE((phase == ASTRA_ASYNC_EXCEPTION) == (exception != NULL));
	task->exception = exception;
	task->pending_phase = phase;
	if (task->executor != NULL) {
		registration(task)->timer = 0;
	}
	task->phase = ASTRA_ASYNC_DRAINING;
	publish(task);
}

static void core_drop(AstraAsyncTask *task) {
	ASTRA_ASYNC_REQUIRE(task != NULL && task->executor == NULL && !task->observation_acquired);
	retire(task, 0);
}

static uint32_t core_pump(AstraAsyncExecutor *executor, uint32_t budget) {
	ASTRA_ASYNC_REQUIRE(executor != NULL && !executor->closed && !executor->pumping);
	executor->pumping = 1;
	if (executor->provider != NULL) {
		unlock_runtime();
		executor->provider->service(executor, 0);
		lock_runtime();
	}
	uint32_t turns = 0;
	while (turns < budget) {
		uint32_t scanned = 0;
		AstraAsyncRegistration *entry = NULL;
		while (scanned++ < executor->capacity) {
			uint32_t slot = executor->cursor;
			executor->cursor = (slot + 1) % executor->capacity;
			if (executor->registrations[slot].ready) {
				entry = &executor->registrations[slot];
				break;
			}
		}
		if (entry == NULL) {
			break;
		}
		entry->ready = 0;
		AstraAsyncTask *task = entry->task;
		ASTRA_ASYNC_REQUIRE(task != NULL && !terminal(task));
		if ((entry->timer || entry->external || (task->waiting != NULL && (!terminal(task->waiting) || !quiescent(task->waiting)))) && !task->cancellation) {
			turns++;
			continue;
		}
		if (task->pending_phase != 0) {
			publish(task);
			turns++;
			continue;
		}
		task->phase = ASTRA_ASYNC_RUNNING;
		task->threaded_busy = 1;
		unlock_runtime();
		task->resume(task);
		lock_runtime();
		ASTRA_ASYNC_REQUIRE(task->phase != ASTRA_ASYNC_RUNNING && task->threaded_busy);
		task->threaded_busy = 0;
		publish(task);
		turns++;
	}
	if (executor->provider != NULL) {
		unlock_runtime();
		executor->provider->service(executor, 0);
		lock_runtime();
	}
	executor->pumping = 0;
	return turns;
}

static int core_advance(AstraAsyncExecutor *executor, uint64_t ticks) {
	ASTRA_ASYNC_REQUIRE(executor != NULL && !executor->closed && !executor->pumping);
	ASTRA_ASYNC_REQUIRE(executor->provider == NULL);
	if (ticks > UINT64_MAX - executor->ticks) {
		return 0;
	}
	executor->ticks += ticks;
	for (uint32_t i = 0; i < executor->capacity; i++) {
		AstraAsyncRegistration *entry = &executor->registrations[i];
		if (entry->timer && entry->deadline <= executor->ticks) {
			entry->timer = 0;
			entry->ready = 1;
		}
	}
	return 1;
}

static int core_advance_next(AstraAsyncExecutor *executor) {
	uint64_t deadline = UINT64_MAX;
	int found = 0;
	for (uint32_t i = 0; i < executor->capacity; i++) {
		AstraAsyncRegistration *entry = &executor->registrations[i];
		if (entry->timer && (!found || entry->deadline < deadline)) {
			deadline = entry->deadline;
			found = 1;
		}
	}
	return found && core_advance(executor, deadline - executor->ticks);
}
static void core_begin_shutdown(AstraAsyncExecutor *executor) {
	ASTRA_ASYNC_REQUIRE(executor != NULL && !executor->closed && !executor->pumping);
	executor->closing = 1;
	for (uint32_t i = 0; i < executor->capacity; ++i) {
		if (executor->registrations[i].task) core_cancel(executor->registrations[i].task);
	}
}
static int core_shutdown_complete(AstraAsyncExecutor *executor) {
	if (!executor->closing || executor->retiring || executor->bridges) {
		return 0;
	}
	for (uint32_t i = 0; i < executor->capacity; i++) {
		AstraAsyncRegistration *entry = &executor->registrations[i];
		if (entry->task != NULL && (!terminal(entry->task) || entry->ready || entry->timer || entry->external || entry->cancel_pending || entry->retained != 0)) {
			return 0;
		}
	}
	return 1;
}
static int core_finish_shutdown(AstraAsyncExecutor *executor) {
	ASTRA_ASYNC_REQUIRE(executor != NULL && !executor->pumping);
	if (executor->closed) {
		return 1;
	}
	if (!core_shutdown_complete(executor) || executor->associated != 0 || (executor->root_admitted && !executor->root_observed)) {
		return 0;
	}
	executor->closed = 1;
	return 1;
}
static int core_observe_root(AstraAsyncExecutor *executor, AstraAsyncTask *root, int transfer) {
	ASTRA_ASYNC_REQUIRE(executor->root == root && root->parent == NULL && !root->observation_acquired && terminal(root) && quiescent(root));
	root->observation_acquired = 1;
	int phase = root->phase;
	executor->root = NULL;
	executor->root_observed = 1;
	retire(root, transfer);
	return phase;
}
static void core_close(AstraAsyncExecutor *executor) {
	ASTRA_ASYNC_REQUIRE(executor != NULL && !executor->pumping && executor->associated == 0 && executor->retiring == 0 && executor->bridges == 0 && (!executor->root_admitted || executor->root_observed));
	if (executor->provider != NULL) {
		unlock_runtime();
		executor->provider->close(executor);
		lock_runtime();
	}
	free(executor->registrations);
	free(executor);
}
static void core_host_cancel(AstraAsyncExecutor *executor, AstraAsyncTask *task) {
	ASTRA_ASYNC_REQUIRE(executor != NULL && task != NULL && (task->executor == NULL || task->executor == executor));
	core_cancel(task);
}
static int core_run(AstraAsyncExecutor *executor, AstraAsyncTask *root, void **exception) {
	ASTRA_ASYNC_REQUIRE(executor != NULL && root != NULL && exception != NULL && !executor->pumping && root->parent == NULL && (root->executor == NULL || root->executor == executor));
	*exception = NULL;
	if (root->executor == NULL && root->phase == ASTRA_ASYNC_CANCELLED) {
		retire(root, 0);
		core_begin_shutdown(executor);
		ASTRA_ASYNC_REQUIRE(core_finish_shutdown(executor));
		return ASTRA_ASYNC_CANCELLED;
	}
	if (root->executor == NULL) {
		int admission = core_start(executor, root, NULL);
		if (admission != ASTRA_ASYNC_ADMITTED) {
			retire(root, 0);
			return -admission;
		}
	} else {
		ASTRA_ASYNC_REQUIRE(executor->root == root && !root->observation_acquired);
	}
	while (!terminal(root)) {
		if (core_pump(executor, executor->capacity) != 0) {
			continue;
		}
		if (executor->provider != NULL) {
			unlock_runtime();
			executor->provider->service(executor, 1);
			lock_runtime();
			continue;
		}
		if (core_advance_next(executor)) {
			/* Virtual timers can otherwise advance forever while a foreign
			 * worker is runnable. Offer publication a bounded host scheduling
			 * turn before the next virtual deadline; ready source work remains
			 * ready and no task or outcome is consumed by this wait. */
			if (executor->bridges) {
				wait_publication(executor);
			}
		} else if (!wait_publication(executor)) {
			abort(); /* No progress: keep live registrations until the fatal contract boundary. */
		}
	}
	int phase = root->phase;
	if (phase == ASTRA_ASYNC_EXCEPTION) {
		*exception = root->exception;
	}
	core_begin_shutdown(executor);
	ASTRA_ASYNC_REQUIRE(core_observe_root(executor, root, phase != ASTRA_ASYNC_CANCELLED) == phase);
	ASTRA_ASYNC_REQUIRE(core_finish_shutdown(executor));
	return phase;
}
static AstraAsyncToken core_token(AstraAsyncTask *task) {
	ASTRA_ASYNC_REQUIRE(task->executor != NULL);
	return task->token;
}
static int core_wake(AstraAsyncExecutor *executor, AstraAsyncToken token) {
	if (token.executor != executor->identity || token.slot >= executor->capacity) {
		return 0;
	}
	AstraAsyncRegistration *entry = &executor->registrations[token.slot];
	if (entry->task == NULL || entry->generation != token.generation || terminal(entry->task)) {
		return 0;
	}
	entry->ready = 1;
	return 1;
}
static int core_retain(AstraAsyncTask *task, const void *backing) {
	ASTRA_ASYNC_REQUIRE(task->executor != NULL && !terminal(task) && backing != NULL);
	AstraAsyncRegistration *entry = registration(task);
	if (entry->retained != 0) {
		return 0;
	}
	entry->backing = backing;
	entry->retained = 1;
	return 1;
}
static int core_observe_release(AstraAsyncExecutor *executor, AstraAsyncToken token) {
	if (token.executor != executor->identity || token.slot >= executor->capacity) {
		return 0;
	}
	AstraAsyncRegistration *entry = &executor->registrations[token.slot];
	if (entry->task == NULL || entry->generation != token.generation || entry->retained == 0) {
		return 0;
	}
	entry->retained = 0;
	entry->backing = NULL;
	if (entry->task->pending_phase != 0) {
		publish(entry->task);
	} else if (entry->task->cancellation) {
		schedule(entry->task);
	}
	return 1;
}
static int core_provider_read(AstraAsyncExecutor *executor, AstraAsyncToken token) {
	if (token.executor != executor->identity || token.slot >= executor->capacity) {
		return -1;
	}
	AstraAsyncRegistration *entry = &executor->registrations[token.slot];
	if (entry->task == NULL || entry->generation != token.generation || entry->retained == 0 || entry->backing == NULL) {
		return -1;
	}
	return *(const unsigned char *)entry->backing;
}

#ifdef ASTRA_ASYNC_TEST_PROTOCOL
static void core_test_generation(AstraAsyncExecutor *executor, uint32_t slot, uint64_t generation) {
	ASTRA_ASYNC_REQUIRE(executor && slot < executor->capacity && !executor->pumping && executor->registrations[slot].task == NULL);
	executor->registrations[slot].generation = generation;
}
#endif

static AstraAsyncExecutor *core_provider_open(uint32_t capacity, const AstraAsyncProvider *provider, void *state) {
	ASTRA_ASYNC_REQUIRE(provider != NULL && state != NULL);
	AstraAsyncExecutor *executor = core_open(capacity);
	if (executor != NULL) {
		executor->provider = provider;
		executor->provider_state = state;
	}
	return executor;
}
static void *core_provider_state(AstraAsyncExecutor *executor, const AstraAsyncProvider *provider) {
	ASTRA_ASYNC_REQUIRE(executor != NULL && executor->provider == provider);
	return executor->provider_state;
}
static int core_provider_ready(AstraAsyncExecutor *executor) {
	for (uint32_t i = 0; i < executor->capacity; i++) {
		if (executor->registrations[i].ready) {
			return 1;
		}
	}
	return 0;
}
static int core_provider_suspend(AstraAsyncTask *task, const void *record) {
	ASTRA_ASYNC_REQUIRE(task->executor != NULL && task->executor->provider != NULL && task->phase == ASTRA_ASYNC_RUNNING);
	AstraAsyncRegistration *entry = registration(task);
	ASTRA_ASYNC_REQUIRE(!entry->external && !entry->external_result && !entry->timer);
	if (!core_retain(task, record)) {
		return 0;
	}
	entry->external = 1;
	entry->external_pc = task->pc;
	task->phase = ASTRA_ASYNC_WAITING;
	return 1;
}
static int core_provider_complete(AstraAsyncExecutor *executor, AstraAsyncToken token, uint32_t pc, int error) {
	if (executor->provider == NULL || token.executor != executor->identity || token.slot >= executor->capacity) {
		return 0;
	}
	AstraAsyncRegistration *entry = &executor->registrations[token.slot];
	if (entry->task == NULL || entry->generation != token.generation || !entry->external || entry->external_pc != pc || entry->retained != 1) {
		return 0;
	}
	entry->external = 0;
	entry->external_error = error;
	entry->external_result = !entry->task->cancellation;
	ASTRA_ASYNC_REQUIRE(core_observe_release(executor, token));
	core_wake(executor, token);
	return 1;
}
static int core_provider_result(AstraAsyncTask *task, uint32_t pc) {
	AstraAsyncRegistration *entry = registration(task);
	ASTRA_ASYNC_REQUIRE(task->executor->provider != NULL && !entry->external && entry->retained == 0 && entry->external_result && entry->external_pc == pc && task->pc == pc);
	entry->external_result = 0;
	return entry->external_error;
}
