/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "../../lib/runtime/async/virtual.h"
#include "context-provider.h"
#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

/* Observe the actual compiler factories/resumes/destructors. The wrappers
 * delegate the original source arguments unchanged. The queued control adds
 * one bounded barrier child before the source handoff. The source controller
 * observes actual queued cancellation before releasing that worker barrier. */
typedef struct TrackedTask {
	AstraAsyncTask *task;
	AstraAsyncResume resume;
	AstraAsyncDestroy destroy;
	unsigned active;
} TrackedTask;
#define M17_TRACKED_TASKS 512u
static TrackedTask tasks[M17_TRACKED_TASKS];
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static _Thread_local AstraAsyncTask *running;
static AstraAsyncTask *selected;
static AstraAsyncFrameAllocator observed_allocator;
static void *(*allocate_frame)(void *, size_t, size_t);
static void (*release_frame)(void *, void *);
static _Atomic unsigned entered, computed, guards, bridge_returned, joined;
static _Atomic unsigned frames, frame_releases, created, destroyed, selected_destroyed;
static _Atomic long worker;
static int mode, disposed_before, baseline_fds, baseline_threads;
static unsigned cases;
static long owner;
static _Atomic long calibrated;
static _Atomic unsigned thread_attempts, thread_created, thread_joined;
static _Atomic unsigned queue_entered, queue_admitted, queue_release, queue_disposed, admission_refused;
static _Atomic unsigned fill_admitted, fill_disposed, fill_entered;
static AstraAsyncExecutor *fill_source, *fill_target;
static AstraAsyncTask *fill_root;
static _Atomic unsigned fill_root_disposed;
#ifdef M17_CONTEXT_BYTE_INPUT
static void *byte_input;
static uint64_t byte_tag;
static _Atomic unsigned byte_releases;
extern void *__real_astra_context17_allocate_mode(AstraContext17 *, uint64_t,
                                                  uint64_t, uint32_t, uint64_t, uint32_t);
extern int __real_astra_context17_release_origin_checked(void *, uint64_t);
void *__wrap_astra_context17_allocate_mode(AstraContext17 *context, uint64_t count,
                                           uint64_t size, uint32_t alignment, uint64_t tag, uint32_t threading) {
	void *pointer = __real_astra_context17_allocate_mode(context, count, size,
	                                                     alignment, tag, threading);
	if (count == 37 && size == 1) {
		assert(pointer && byte_input == NULL && threading == 2 && tag != 0);
		assert(astra_context17_origin(pointer, tag) == context);
		byte_input = pointer;
		byte_tag = tag;
	}
	return pointer;
}
int __wrap_astra_context17_release_origin_checked(void *pointer, uint64_t tag) {
	if (pointer == byte_input) {
		assert(tag == byte_tag && atomic_fetch_add(&byte_releases, 1) == 0);
		assert(atomic_load(&guards) == 1 && atomic_load(&frame_releases) == 0);
		AstraContext17 *context = astra_context17_origin(pointer, tag);
		AstraContext17Snapshot state;
		assert(astra_context17_snapshot(context, &state) == ASTRA_CONTEXT17_OK);
		assert(state.anchors == 0 && state.closed && state.live >= 2);
	}
	return __real_astra_context17_release_origin_checked(pointer, tag);
}
#endif

static int inventory(const char *path) {
	DIR *directory = opendir(path);
	assert(directory);
	int count = 0;
	struct dirent *entry;
	while ((entry = readdir(directory)))
		if (entry->d_name[0] != '.') ++count;
	assert(closedir(directory) == 0);
	return count;
}
static void wait_threads(void) {
	struct timespec start, now, delay = {.tv_nsec = 1000000};
	assert(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
	while (inventory("/proc/self/task") != baseline_threads) {
		assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0 && now.tv_sec - start.tv_sec < 8);
		assert(nanosleep(&delay, NULL) == 0);
	}
}
int __real_pthread_create(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
int __real_pthread_join(pthread_t, void **);
int __wrap_pthread_create(pthread_t *thread, const pthread_attr_t *attributes, void *(*entry)(void *), void *argument) {
	if (mode != 6 && mode != 7) return __real_pthread_create(thread, attributes, entry, argument);
	unsigned attempt = atomic_fetch_add(&thread_attempts, 1);
	if (attempt == (mode == 6 ? 0u : 1u)) return EAGAIN;
	assert(mode == 7 && attempt == 0);
	int result = __real_pthread_create(thread, attributes, entry, argument);
	assert(result == 0 && atomic_fetch_add(&thread_created, 1) == 0);
	return result;
}
int __wrap_pthread_join(pthread_t thread, void **value) {
	int result = __real_pthread_join(thread, value);
	if (mode == 6 || mode == 7) assert(result == 0 && atomic_fetch_add(&thread_joined, 1) == 0);
	return result;
}
static void *calibrate(void *argument) {
	atomic_store(&calibrated, syscall(SYS_gettid));
	return argument;
}
void cancellation_prepare(void) {
	owner = syscall(SYS_gettid);
	/* TSAN starts a persistent helper on the first pthread creation. Measure
	 * after a real joined calibration, with no suppression or count offset. */
	pthread_t thread;
	assert(pthread_create(&thread, NULL, calibrate, NULL) == 0);
	assert(pthread_join(thread, NULL) == 0);
	/* The proc TID may briefly remain after join, as independently probed in
	 * join-retirement-probe.c. Wait for this exact native thread to disappear. */
	char path[128];
	assert(snprintf(path, sizeof(path), "/proc/self/task/%ld", atomic_load(&calibrated)) > 0);
	struct timespec start, now, delay = {.tv_nsec = 1000000};
	struct stat state;
	assert(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
	while (stat(path, &state) == 0) {
		assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0 && now.tv_sec - start.tv_sec < 8);
		assert(nanosleep(&delay, NULL) == 0);
	}
	assert(errno == ENOENT);
	baseline_fds = inventory("/proc/self/fd");
	baseline_threads = inventory("/proc/self/task");
}
int cancellation_rounds(void) {
	const char *setting = getenv("M17_CANCEL_ROUNDS");
	int rounds = setting ? atoi(setting) : 1;
	assert(rounds >= 1 && rounds <= 64);
	return rounds;
}
static TrackedTask *find(AstraAsyncTask *task) {
	for (unsigned i = 0; i < M17_TRACKED_TASKS; ++i)
		if (tasks[i].task == task) return &tasks[i];
	abort();
}
static void observe_resume(AstraAsyncTask *task) {
	assert(pthread_mutex_lock(&lock) == 0);
	TrackedTask *entry = find(task);
	AstraAsyncResume resume = entry->resume;
	assert(entry->active++ == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	/* A distinct explicit executor may be pumped within a native boundary.
	 * Each individual frame still has exactly one active resume. */
	AstraAsyncTask *previous = running;
	running = task;
	resume(task);
	assert(running == task);
	running = previous;
	assert(pthread_mutex_lock(&lock) == 0);
	assert(find(task)->active-- == 1);
	assert(pthread_mutex_unlock(&lock) == 0);
}
static void observe_destroy(AstraAsyncTask *task, int discard) {
	assert(pthread_mutex_lock(&lock) == 0);
	TrackedTask *entry = find(task);
	AstraAsyncDestroy destroy = entry->destroy;
	assert(entry->active == 0);
	assert(pthread_mutex_unlock(&lock) == 0);
	if (task == selected) {
		assert(astra_async_phase(task) == (mode >= 5 ? ASTRA_ASYNC_NEW : (mode < 2 || mode == 4) ? ASTRA_ASYNC_CANCELLED
		                                                             : mode == 2                 ? ASTRA_ASYNC_SUCCESS
		                                                                                         : ASTRA_ASYNC_EXCEPTION));
		assert(atomic_fetch_add(&selected_destroyed, 1) == 0);
	}
	destroy(task, discard);
	assert(pthread_mutex_lock(&lock) == 0);
	*find(task) = (TrackedTask){0};
	assert(pthread_mutex_unlock(&lock) == 0);
	atomic_fetch_add(&destroyed, 1);
}
static AstraAsyncTask *track(AstraAsyncTask *task, AstraAsyncResume resume, AstraAsyncDestroy destroy) {
	assert(task);
	assert(pthread_mutex_lock(&lock) == 0);
	unsigned slot;
	for (slot = 0; slot < M17_TRACKED_TASKS && tasks[slot].task; ++slot) {
	}
	assert(slot < M17_TRACKED_TASKS);
	tasks[slot] = (TrackedTask){task, resume, destroy, 0};
	assert(pthread_mutex_unlock(&lock) == 0);
	atomic_fetch_add(&created, 1);
	return task;
}
AstraAsyncTask *__real_astra_async_new(size_t, size_t, AstraAsyncResume, AstraAsyncDestroy, AstraAsyncTask *);
AstraAsyncTask *__wrap_astra_async_new(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy, AstraAsyncTask *parent) {
	return track(__real_astra_async_new(size, alignment, observe_resume, observe_destroy, parent), resume, destroy);
}
static void *observed_allocate(void *context, size_t size, size_t alignment) {
	void *pointer = allocate_frame(context, size, alignment);
	assert(pointer && astra_context17_origin(pointer, UINT64_C(0x6173747261667231)) == context);
	assert(atomic_fetch_add(&frames, 1) == 0);
	return pointer;
}
static void observed_release(void *context, void *pointer) {
	assert(atomic_load(&selected_destroyed) == 1 && atomic_load(&guards) == 1);
#ifdef M17_CONTEXT_BYTE_INPUT
	assert(atomic_load(&byte_releases) == 1);
#endif
	assert(m17_custom_provider_retired() == disposed_before);
	AstraContext17Snapshot snapshot;
	assert(astra_context17_snapshot(context, &snapshot) == ASTRA_CONTEXT17_OK);
	assert(snapshot.anchors == 0 && snapshot.closed && snapshot.live == 1);
	assert(astra_context17_origin(pointer, UINT64_C(0x6173747261667231)) == context);
	release_frame(context, pointer);
	assert(m17_custom_provider_retired() == disposed_before + 1);
	assert(atomic_fetch_add(&frame_releases, 1) == 0);
}
AstraAsyncTask *__real_astra_async_new_allocated(size_t, size_t, AstraAsyncResume, AstraAsyncDestroy, AstraAsyncTask *, const AstraAsyncFrameAllocator *, void *);
AstraAsyncTask *__wrap_astra_async_new_allocated(size_t size, size_t alignment, AstraAsyncResume resume, AstraAsyncDestroy destroy,
                                                 AstraAsyncTask *parent, const AstraAsyncFrameAllocator *allocator, void *context) {
	assert(!selected && allocator && allocator->threading == 2 && context);
	allocate_frame = allocator->allocate;
	release_frame = allocator->release;
	observed_allocator = *allocator;
	observed_allocator.allocate = observed_allocate;
	observed_allocator.release = observed_release;
	selected = track(__real_astra_async_new_allocated(size, alignment, observe_resume, observe_destroy, parent, &observed_allocator, context), resume, destroy);
	return selected;
}
/* The public Astra victim remains queued behind this separate test barrier.
 * Its source-generated resume/destructor and selected context are unchanged. */
static void queue_barrier_destroy(AstraAsyncTask *task, int discard) {
	(void)discard;
	assert(astra_async_phase(task) == ASTRA_ASYNC_CANCELLED);
	assert(atomic_fetch_add(&queue_disposed, 1) == 0);
}
static void queue_barrier(AstraAsyncTask *task) {
	assert((mode == 4 || mode == 8) && running == task && task != selected);
	atomic_store(&worker, syscall(SYS_gettid));
	assert(atomic_fetch_add(&queue_entered, 1) == 0);
	struct timespec start, now, delay = {.tv_nsec = 1000000};
	assert(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
	while (!atomic_load(&queue_release) || !astra_async_cancel_requested(task)) {
		assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0 && now.tv_sec - start.tv_sec < 8);
		assert(atomic_load(&entered) == 0 && atomic_load(&computed) == 0);
		if (mode == 4) assert(atomic_load(&guards) == 0 && atomic_load(&frame_releases) == 0);
		assert(nanosleep(&delay, NULL) == 0);
	}
	assert(astra_async_cancel_requested(task) && astra_async_cancel_scope(task));
	astra_async_complete(task, ASTRA_ASYNC_CANCELLED, NULL);
}
static void queue_filler_destroy(AstraAsyncTask *task, int discard) {
	(void)discard;
	assert(mode == 8 && astra_async_phase(task) == (*(int *)astra_async_data(task) ? ASTRA_ASYNC_CANCELLED : ASTRA_ASYNC_NEW));
	atomic_fetch_add(&fill_disposed, 1);
}
static void queue_filler(AstraAsyncTask *task) {
	assert(mode == 8 && running == task && astra_async_cancel_requested(task));
	assert(astra_async_cancel_scope(task));
	atomic_fetch_add(&fill_entered, 1);
	astra_async_complete(task, ASTRA_ASYNC_CANCELLED, NULL);
}
static void occupy_worker(AstraAsyncExecutor *target, AstraAsyncTask *parent) {
	AstraAsyncTask *barrier = astra_async_new(sizeof(int), _Alignof(int), queue_barrier, queue_barrier_destroy, parent);
	assert(barrier && astra_async_bridge_start(target, barrier, parent) == ASTRA_ASYNC_ADMITTED);
	struct timespec start, now, delay = {.tv_nsec = 1000000};
	assert(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
	while (!atomic_load(&queue_entered)) {
		assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0 && now.tv_sec - start.tv_sec < 8);
		assert(nanosleep(&delay, NULL) == 0);
	}
}
static void fill_parent_destroy(AstraAsyncTask *task, int discard) {
	(void)discard;
	assert(mode == 8 && astra_async_phase(task) == ASTRA_ASYNC_CANCELLED);
	assert(atomic_fetch_add(&fill_root_disposed, 1) == 0);
}
static void fill_parent_resume(AstraAsyncTask *task) {
	assert(mode == 8 && task == fill_root && running == task);
	if (astra_async_cancel_requested(task)) {
		if (astra_async_cancel_scope(task)) astra_async_complete(task, ASTRA_ASYNC_CANCELLED, NULL);
		return;
	}
	assert(atomic_load(&fill_admitted) == 0);
	occupy_worker(fill_target, task);
	int full = 0;
	for (unsigned i = 0; i < M17_TRACKED_TASKS - 5; ++i) {
		AstraAsyncTask *filler = astra_async_new(sizeof(int), _Alignof(int), queue_filler, queue_filler_destroy, task);
		assert(filler);
		*(int *)astra_async_data(filler) = 1;
		int status = astra_async_bridge_start(fill_target, filler, task);
		if (status == ASTRA_ASYNC_CAPACITY) {
			*(int *)astra_async_data(filler) = 0;
			astra_async_drop(filler);
			full = 1;
			break;
		}
		assert(status == ASTRA_ASYNC_ADMITTED);
		atomic_fetch_add(&fill_admitted, 1);
	}
	assert(full && atomic_load(&fill_admitted) > 8 && atomic_load(&fill_disposed) == 1);
	assert(astra_async_delay(task, 1));
}
int __real_astra_async_bridge_wait(AstraAsyncTask *, AstraAsyncTask *, AstraAsyncExecutor *, int);
int __wrap_astra_async_bridge_wait(AstraAsyncTask *parent, AstraAsyncTask *child, AstraAsyncExecutor *target, int discard) {
	if (mode == 5 && child == selected) {
		int result = __real_astra_async_bridge_wait(parent, child, target, discard);
		assert(result == ASTRA_ASYNC_CLOSED && !discard);
		assert(atomic_load(&entered) == 0 && atomic_load(&computed) == 0);
		assert(atomic_load(&selected_destroyed) == 1 && atomic_load(&guards) == 1 && atomic_load(&frame_releases) == 1);
		assert(m17_custom_provider_retired() == disposed_before + 1);
		assert(atomic_fetch_add(&admission_refused, 1) == 0);
		return result;
	}
	if ((mode != 4 && mode != 8) || child != selected) return __real_astra_async_bridge_wait(parent, child, target, discard);
	assert(syscall(SYS_gettid) == owner && !discard && atomic_load(&queue_admitted) == 0);
	if (mode == 8) {
		assert(!fill_source && !fill_target && !fill_root);
		fill_source = astra_async_virtual_open(M17_TRACKED_TASKS);
		fill_target = target;
		fill_root = astra_async_new(sizeof(int), _Alignof(int), fill_parent_resume, fill_parent_destroy, NULL);
		assert(fill_source && fill_root && astra_async_start(fill_source, fill_root, NULL) == ASTRA_ASYNC_ADMITTED);
		assert(astra_async_pump(fill_source, 1) == 1);
		int result = __real_astra_async_bridge_wait(parent, child, target, discard);
		assert(result == ASTRA_ASYNC_CAPACITY);
		assert(atomic_load(&selected_destroyed) == 1 && atomic_load(&guards) == 1 && atomic_load(&frame_releases) == 1);
		assert(m17_custom_provider_retired() == disposed_before + 1);
		assert(atomic_fetch_add(&admission_refused, 1) == 0);
		return result;
	}
	occupy_worker(target, parent);
	int result = __real_astra_async_bridge_wait(parent, child, target, discard);
	assert(result == ASTRA_ASYNC_ADMITTED && atomic_load(&entered) == 0);
	assert(atomic_fetch_add(&queue_admitted, 1) == 0);
	return result;
}
int cancellation_queued(void) {
	return (int)atomic_load(&queue_admitted);
}
int cancellation_admission_refused(void) {
	return (int)atomic_load(&admission_refused);
}
void cancellation_release_full_queue(void) {
	assert(mode == 8 && syscall(SYS_gettid) == owner && atomic_load(&admission_refused) == 1);
	assert(atomic_load(&selected_destroyed) == 1 && atomic_load(&guards) == 1 && atomic_load(&frame_releases) == 1);
	assert(atomic_fetch_add(&queue_release, 1) == 0);
	astra_async_cancel(fill_root);
	struct timespec start, now, delay = {.tv_nsec = 1000000};
	assert(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
	while (astra_async_phase(fill_root) != ASTRA_ASYNC_CANCELLED) {
		(void)astra_async_pump(fill_source, 16);
		assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0 && now.tv_sec - start.tv_sec < 8);
		assert(nanosleep(&delay, NULL) == 0);
	}
	astra_async_begin_shutdown(fill_source);
	assert(astra_async_observe_root(fill_source, fill_root, 0) == ASTRA_ASYNC_CANCELLED);
	assert(astra_async_finish_shutdown(fill_source));
	astra_async_close(fill_source);
	fill_source = NULL;
	fill_target = NULL;
	fill_root = NULL;
}
int cancellation_queue_cancelled(void) {
	assert(mode == 4 && atomic_load(&queue_admitted) == 1 && atomic_load(&queue_release) == 0);
	assert(atomic_load(&selected_destroyed) == 0 && atomic_load(&guards) == 0 && atomic_load(&entered) == 0);
	return astra_async_cancel_requested(selected);
}
void cancellation_abort_queue(void) {
	if (mode == 8 && fill_source)
		cancellation_release_full_queue();
	else
		atomic_store(&queue_release, 1);
}
void cancellation_release_queue(void) {
	assert(syscall(SYS_gettid) == owner && cancellation_queue_cancelled());
	AstraContext17 *context = astra_context17_origin(astra_async_data(selected), UINT64_C(0x6173747261667231));
	AstraContext17Snapshot snapshot;
	assert(astra_context17_snapshot(context, &snapshot) == ASTRA_CONTEXT17_OK);
	unsigned expected_live = 2;
#ifdef M17_CONTEXT_BYTE_INPUT
	expected_live = 3;
#endif
	assert(snapshot.closed && snapshot.anchors == 0 && snapshot.live == expected_live);
	assert(atomic_load(&frame_releases) == 0 && m17_custom_provider_retired() == disposed_before);
	assert(atomic_fetch_add(&queue_release, 1) == 0);
}
void cancellation_begin(int requested_mode) {
	assert(syscall(SYS_gettid) == owner && requested_mode >= 0 && requested_mode < 9);
	mode = requested_mode;
#ifdef M17_CONTEXT_BYTE_INPUT
	byte_input = NULL;
	byte_tag = 0;
	atomic_store(&byte_releases, 0);
#endif
	selected = NULL;
	disposed_before = m17_custom_provider_retired();
	atomic_store(&entered, 0);
	atomic_store(&computed, 0);
	atomic_store(&guards, 0);
	atomic_store(&bridge_returned, 0);
	atomic_store(&joined, 0);
	atomic_store(&worker, 0);
	atomic_store(&frames, 0);
	atomic_store(&frame_releases, 0);
	atomic_store(&selected_destroyed, 0);
	atomic_store(&created, 0);
	atomic_store(&destroyed, 0);
	atomic_store(&thread_attempts, 0);
	atomic_store(&thread_created, 0);
	atomic_store(&thread_joined, 0);
	atomic_store(&queue_entered, 0);
	atomic_store(&queue_admitted, 0);
	atomic_store(&queue_release, 0);
	atomic_store(&queue_disposed, 0);
	atomic_store(&admission_refused, 0);
	atomic_store(&fill_admitted, 0);
	atomic_store(&fill_disposed, 0);
	atomic_store(&fill_entered, 0);
	atomic_store(&fill_root_disposed, 0);
	assert(inventory("/proc/self/fd") == baseline_fds);
	wait_threads();
}
void cancellation_gate(int requested_mode) {
	assert(mode == requested_mode && mode != 0 && mode != 4 && mode < 5 && running == selected && syscall(SYS_gettid) != owner);
	atomic_store(&worker, syscall(SYS_gettid));
	AstraContext17Snapshot snapshot;
	AstraContext17 *context = astra_context17_origin(astra_async_data(running), UINT64_C(0x6173747261667231));
	assert(astra_context17_snapshot(context, &snapshot) == ASTRA_CONTEXT17_OK);
	unsigned expected_live = 2;
#ifdef M17_CONTEXT_BYTE_INPUT
	expected_live = 3;
#endif
	assert(snapshot.anchors == 0 && snapshot.closed && snapshot.live == expected_live);
	assert(atomic_fetch_add(&entered, 1) == 0);
	if (mode == 1) {
		struct timespec start, now, delay = {.tv_nsec = 1000000};
		assert(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
		while (!astra_async_cancel_requested(running)) {
			assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0 && now.tv_sec - start.tv_sec < 8);
			assert(atomic_load(&guards) == 0 && atomic_load(&frame_releases) == 0 && m17_custom_provider_retired() == disposed_before);
			assert(nanosleep(&delay, NULL) == 0);
		}
		assert(atomic_load(&guards) == 0 && atomic_load(&frame_releases) == 0);
	}
}
void cancellation_computed(int value) {
	/* Independent recurrence; the actual work and owning input are Astra. */
	int expected = 17;
	for (int i = 0; i < 131071; ++i)
		expected = (expected * 19 + ((i % 37) * 23 + 41) % 251 + i % 251) % 65521;
	assert(running == selected && value == expected && atomic_fetch_add(&computed, 1) == 0);
}
void cancellation_guard_retired(void) {
	long current = syscall(SYS_gettid);
	assert(current == owner || current == atomic_load(&worker));
	assert(atomic_load(&computed) == ((mode == 0 || mode >= 4) ? 0u : 1u));
	assert(atomic_fetch_add(&guards, 1) == 0);
}
int cancellation_entered(void) {
	return (int)atomic_load(&entered);
}
int cancellation_bridge_finished(void) {
	return (int)atomic_load(&bridge_returned);
}
void cancellation_bridge_returned(void) {
	assert(mode != 1 && mode != 4 && mode != 8 && atomic_load(&selected_destroyed) == 1 && atomic_load(&frame_releases) == 1);
	assert(atomic_fetch_add(&bridge_returned, 1) == 0);
}
void __real_astra_async_worker_pool_close(AstraAsyncExecutor *);
void __wrap_astra_async_worker_pool_close(AstraAsyncExecutor *pool) {
	assert(syscall(SYS_gettid) == owner);
	__real_astra_async_worker_pool_close(pool);
	assert(atomic_fetch_add(&joined, 1) == 0);
}
void cancellation_joined(void) {
	assert(atomic_load(&selected_destroyed) == 1 && atomic_load(&frame_releases) == 1 && atomic_load(&joined) == 1);
	assert(atomic_load(&bridge_returned) == ((mode == 1 || mode == 4 || mode == 8) ? 0u : 1u));
}
void cancellation_case_finished(void) {
	unsigned expected_tasks = mode == 8 ? 6u + atomic_load(&fill_admitted) : mode >= 6 ? 1u
	                                                                     : mode == 4   ? 4u
	                                                                                   : 3u;
	assert(atomic_load(&guards) == 1 && atomic_load(&created) == expected_tasks && atomic_load(&destroyed) == expected_tasks);
	assert(atomic_load(&queue_entered) == (mode == 4 || mode == 8 ? 1u : 0u));
	assert(atomic_load(&queue_admitted) == (mode == 4 ? 1u : 0u));
	assert(atomic_load(&queue_release) == (mode == 4 || mode == 8 ? 1u : 0u));
	assert(atomic_load(&queue_disposed) == (mode == 4 || mode == 8 ? 1u : 0u));
	assert(atomic_load(&admission_refused) == (mode == 5 || mode == 8 ? 1u : 0u));
	assert(atomic_load(&fill_disposed) == (mode == 8 ? atomic_load(&fill_admitted) + 1 : 0));
	assert(atomic_load(&fill_entered) == atomic_load(&fill_admitted));
	assert(atomic_load(&fill_root_disposed) == (mode == 8 ? 1u : 0u));
	assert(!fill_source && !fill_target && !fill_root);
	if (mode >= 4) assert(atomic_load(&entered) == 0 && atomic_load(&computed) == 0);
	assert(atomic_load(&thread_attempts) == (mode == 6 ? 1u : mode == 7 ? 2u
	                                                                    : 0u));
	assert(atomic_load(&thread_created) == (mode == 7 ? 1u : 0u));
	assert(atomic_load(&thread_joined) == (mode == 7 ? 1u : 0u));
	assert(atomic_load(&frames) == 1 && atomic_load(&frame_releases) == 1 && atomic_load(&joined) == (mode == 6 || mode == 7 ? 0u : 1u));
	assert(m17_custom_provider_retired() == disposed_before + 1);
	assert(inventory("/proc/self/fd") == baseline_fds);
	wait_threads();
	assert(pthread_mutex_lock(&lock) == 0);
	for (unsigned i = 0; i < M17_TRACKED_TASKS; ++i)
		assert(tasks[i].task == NULL);
	assert(pthread_mutex_unlock(&lock) == 0);
	if (mode == 8) fprintf(stderr, "M17 full admission: queued=%u resumed=%u disposed=%u victim=%u frame=%u guard=%u pool_join=%u fd=%d threads=%d\n",
		                   atomic_load(&fill_admitted), atomic_load(&fill_entered), atomic_load(&fill_disposed),
		                   atomic_load(&selected_destroyed), atomic_load(&frame_releases), atomic_load(&guards),
		                   atomic_load(&joined), inventory("/proc/self/fd"), inventory("/proc/self/task"));
	++cases;
}
int cancellation_finish(void) {
	assert(cases == (unsigned)cancellation_rounds() * 9);
	puts("source cancellation: cold, worker start failure, full/closed admission, queued, executing, published success/error; exact context/frame/capture retirement and FD/thread baselines");
	return 0;
}
