// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
/* Included after task-core17.c by hosted pthread entry units. */
// The source-owned frame, parent tree, generation tokens and outcome protocol
// stay in the existing core. Only queue dispatch and synchronization differ.
struct threaded_pool {
	AstraAsyncExecutor *executor;
	struct threaded_pool *next;
	pthread_t workers[8];
	uint32_t worker_count;
	uint32_t active;
	uint64_t turns;
	uint64_t birth;
	int stopping;
};

static pthread_mutex_t runtime_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t runtime_changed;
static pthread_once_t runtime_once = PTHREAD_ONCE_INIT;
static struct threaded_pool *pools;

static void initialize_runtime(void) {
	pthread_condattr_t attributes;
	ASTRA_ASYNC_REQUIRE(pthread_condattr_init(&attributes) == 0);
	ASTRA_ASYNC_REQUIRE(pthread_condattr_setclock(&attributes, CLOCK_MONOTONIC) == 0);
	ASTRA_ASYNC_REQUIRE(pthread_cond_init(&runtime_changed, &attributes) == 0);
	ASTRA_ASYNC_REQUIRE(pthread_condattr_destroy(&attributes) == 0);
}

static void lock_runtime(void) {
	ASTRA_ASYNC_REQUIRE(pthread_once(&runtime_once, initialize_runtime) == 0);
	ASTRA_ASYNC_REQUIRE(pthread_mutex_lock(&runtime_lock) == 0);
}

static void unlock_runtime(void) {
	ASTRA_ASYNC_REQUIRE(pthread_cond_broadcast(&runtime_changed) == 0);
	ASTRA_ASYNC_REQUIRE(pthread_mutex_unlock(&runtime_lock) == 0);
}

static uint64_t milliseconds(void) {
	struct timespec now;
	ASTRA_ASYNC_REQUIRE(clock_gettime(CLOCK_MONOTONIC, &now) == 0);
	return (uint64_t)now.tv_sec * 1000 + (uint64_t)now.tv_nsec / 1000000;
}

static struct threaded_pool *pool_for(AstraAsyncExecutor *executor) {
	for (struct threaded_pool *pool = pools; pool; pool = pool->next)
		if (pool->executor == executor)
			return pool;
	return NULL;
}

static void wait_short(void) {
	struct timespec deadline;
	ASTRA_ASYNC_REQUIRE(clock_gettime(CLOCK_MONOTONIC, &deadline) == 0);
	deadline.tv_nsec += 1000000;
	if (deadline.tv_nsec >= 1000000000) {
		++deadline.tv_sec;
		deadline.tv_nsec -= 1000000000;
	}
	int status = pthread_cond_timedwait(&runtime_changed, &runtime_lock, &deadline);
	ASTRA_ASYNC_REQUIRE(status == 0 || status == ETIMEDOUT);
}
static int wait_publication(AstraAsyncExecutor *executor) {
	if (executor->bridges == 0) return 0;
	/* A newly advanced virtual timer is already ready. Release the metadata
	 * lock for one notified/bounded turn so repeated source polling cannot
	 * monopolize the host while a bridge target needs that same lock. */
	if (core_provider_ready(executor)) {
		wait_short();
		return 1;
	}
	while (!core_provider_ready(executor) && executor->bridges != 0 && !executor->closed)
		ASTRA_ASYNC_REQUIRE(pthread_cond_wait(&runtime_changed, &runtime_lock) == 0);
	return 1;
}

static void *worker_entry(void *argument) {
	struct threaded_pool *pool = argument;
	AstraAsyncExecutor *executor = pool->executor;
	lock_runtime();
	uint32_t worker_identity = 0;
	for (uint32_t i = 0; i < pool->worker_count; ++i)
		if (pthread_equal(pool->workers[i], pthread_self()))
			worker_identity = i + 1;
	ASTRA_ASYNC_REQUIRE(worker_identity != 0);
	while (!pool->stopping) {
		uint64_t elapsed = milliseconds() - pool->birth;
		ASTRA_ASYNC_REQUIRE(elapsed >= executor->ticks);
		if (!executor->closed)
			ASTRA_ASYNC_REQUIRE(core_advance(executor, elapsed - executor->ticks));
		AstraAsyncRegistration *entry = NULL;
		for (uint32_t scanned = 0; scanned < executor->capacity; ++scanned) {
			uint32_t slot = executor->cursor;
			executor->cursor = (slot + 1) % executor->capacity;
			AstraAsyncRegistration *candidate = &executor->registrations[slot];
			if (candidate->ready && candidate->task && !candidate->task->threaded_busy &&
			    (pool->worker_count == 1 || candidate->task->threaded_last_worker != worker_identity)) {
				entry = candidate;
				break;
			}
		}
		/* Prefer migration when another worker can take the next resume. A
		 * busy peer must not prevent this idle worker from resuming its own
		 * ready task: otherwise two long-lived lanes can serialize behind the
		 * mandatory alternation rule. Busy ownership and round-robin selection
		 * remain unchanged. The first suspension still migrates before this
		 * fallback is eligible; publication follows actual resume return. */
		if (!entry && pool->active != 0) {
			for (uint32_t scanned = 0; scanned < executor->capacity; ++scanned) {
				uint32_t slot = executor->cursor;
				executor->cursor = (slot + 1) % executor->capacity;
				AstraAsyncRegistration *candidate = &executor->registrations[slot];
				if (candidate->ready && candidate->task && !candidate->task->threaded_busy && candidate->task->threaded_migrated) {
					entry = candidate;
					break;
				}
			}
		}
		if (!entry) {
			wait_short();
			continue;
		}
		entry->ready = 0;
		AstraAsyncTask *task = entry->task;
		ASTRA_ASYNC_REQUIRE(!terminal(task));
		if ((entry->timer || (task->waiting && !terminal(task->waiting))) && !task->cancellation)
			continue;
		if (task->pending_phase) {
			publish(task);
			ASTRA_ASYNC_REQUIRE(pthread_cond_broadcast(&runtime_changed) == 0);
			continue;
		}
		task->threaded_busy = 1;
		if (task->threaded_last_worker && task->threaded_last_worker != worker_identity) {
			task->threaded_migrated = 1;
		}
		task->threaded_last_worker = worker_identity;
		task->phase = ASTRA_ASYNC_RUNNING;
		++pool->active;
		unlock_runtime();
		task->resume(task);
		lock_runtime();
		ASTRA_ASYNC_REQUIRE(task->phase != ASTRA_ASYNC_RUNNING && task->threaded_busy);
		task->threaded_busy = 0;
		--pool->active;
		++pool->turns;
		/* Cancellation can arrive after the native entry check and before a
		 * suspension arms its timer. Reassert it after the running frame has
		 * returned, so that suspension cannot erase the cancellation wakeup. */
		if (task->cancellation) {
			registration(task)->timer = 0;
			schedule(task);
		}
		// Publication and parent wakeup happen only after the native resume has
		// actually returned; another worker cannot retire a running frame.
		publish(task);
		ASTRA_ASYNC_REQUIRE(pthread_cond_broadcast(&runtime_changed) == 0);
	}
	unlock_runtime();
	return NULL;
}

static AstraAsyncExecutor *worker_open(uint32_t workers) {
	if (workers < 1 || workers > 8)
		return NULL;
	lock_runtime();
	AstraAsyncExecutor *executor = core_open(256);
	struct threaded_pool *pool = executor ? calloc(1, sizeof(*pool)) : NULL;
	if (!pool) {
		if (executor)
			core_close(executor);
		unlock_runtime();
		return NULL;
	}
	pool->executor = executor;
	executor->threaded = 1;
	pool->birth = milliseconds();
	pool->next = pools;
	pools = pool;
	for (uint32_t i = 0; i < workers; ++i) {
		if (pthread_create(&pool->workers[i], NULL, worker_entry, pool) != 0) {
			pool->stopping = 1;
			unlock_runtime();
			for (uint32_t j = 0; j < pool->worker_count; ++j)
				ASTRA_ASYNC_REQUIRE(pthread_join(pool->workers[j], NULL) == 0);
			lock_runtime();
			struct threaded_pool **link = &pools;
			while (*link != pool) {
				ASTRA_ASYNC_REQUIRE(*link);
				link = &(*link)->next;
			}
			*link = pool->next;
			core_close(executor);
			free(pool);
			unlock_runtime();
			return NULL;
		}
		++pool->worker_count;
	}
	unlock_runtime();
	return executor;
}

static int worker_run(AstraAsyncExecutor *executor, AstraAsyncTask *root, void **exception) {
	lock_runtime();
	struct threaded_pool *pool = pool_for(executor);
	ASTRA_ASYNC_REQUIRE(pool && root && exception && root->parent == NULL);
	*exception = NULL;
	if (!root->executor && root->phase == ASTRA_ASYNC_CANCELLED) {
		retire(root, 0);
		core_begin_shutdown(executor);
		ASTRA_ASYNC_REQUIRE(core_finish_shutdown(executor));
		unlock_runtime();
		return ASTRA_ASYNC_CANCELLED;
	}
	if (!root->executor) {
		int admission = core_start(executor, root, NULL);
		if (admission != ASTRA_ASYNC_ADMITTED) {
			retire(root, 0);
			unlock_runtime();
			return -admission;
		}
	} else {
		ASTRA_ASYNC_REQUIRE(executor->root == root && !root->observation_acquired);
	}
	ASTRA_ASYNC_REQUIRE(pthread_cond_broadcast(&runtime_changed) == 0);
	while (!terminal(root) || pool->active || executor->retiring)
		ASTRA_ASYNC_REQUIRE(pthread_cond_wait(&runtime_changed, &runtime_lock) == 0);
	int phase = root->phase;
	if (phase == ASTRA_ASYNC_EXCEPTION)
		*exception = root->exception;
	core_begin_shutdown(executor);
	ASTRA_ASYNC_REQUIRE(core_observe_root(executor, root, phase != ASTRA_ASYNC_CANCELLED) == phase);
	ASTRA_ASYNC_REQUIRE(core_finish_shutdown(executor));
	unlock_runtime();
	return phase;
}

static uint32_t worker_pump(AstraAsyncExecutor *executor, uint32_t budget) {
	lock_runtime();
	struct threaded_pool *pool = pool_for(executor);
	ASTRA_ASYNC_REQUIRE(pool && !executor->closed);
	uint64_t before = pool->turns;
	if (budget)
		wait_short();
	uint64_t turns = pool->turns - before;
	unlock_runtime();
	return turns > budget ? budget : (uint32_t)turns;
}

static void worker_close(AstraAsyncExecutor *executor) {
	lock_runtime();
	struct threaded_pool *pool = pool_for(executor);
	ASTRA_ASYNC_REQUIRE(pool && !pool->active && !executor->retiring && executor->associated == 0);
	pool->stopping = 1;
	unlock_runtime();
	for (uint32_t i = 0; i < pool->worker_count; ++i)
		ASTRA_ASYNC_REQUIRE(pthread_join(pool->workers[i], NULL) == 0);
	lock_runtime();
	struct threaded_pool **link = &pools;
	while (*link != pool) {
		ASTRA_ASYNC_REQUIRE(*link != NULL);
		link = &(*link)->next;
	}
	*link = pool->next;
	core_close(executor);
	free(pool);
	unlock_runtime();
}
