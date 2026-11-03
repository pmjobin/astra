/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "../../lib/runtime/async/virtual.h"
#include "../../lib/runtime/async/linux.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

/* Protocol supplement. Application algorithms are qualified separately in Astra. */
typedef struct Frame {
	AstraAsyncExecutor *targets[2];
	AstraAsyncTask *children[3];
	AstraLinuxPayload *payload;
	int identity, mode, value;
} Frame;

static _Atomic unsigned entered, retired, submitted, completed;
static _Atomic long worker_ids[2];
static long owner;
static int exception_identity;
static AstraAsyncExecutor *io_executor;
static AstraAsyncTask *root_task;

static void dispose(AstraAsyncTask *task, int discard) {
	(void)discard;
	Frame *frame = astra_async_data(task);
	unsigned bit = 1u << frame->identity;
	assert(!(atomic_fetch_or(&retired, bit) & bit));
}

static void cancellation(AstraAsyncTask *task) {
	if (astra_async_cancel_scope(task)) astra_async_complete(task, ASTRA_ASYNC_CANCELLED, NULL);
}

static void compute(AstraAsyncTask *task) {
	Frame *frame = astra_async_data(task);
	assert(frame->identity == 2 || frame->identity == 3);
	if (astra_async_cancel_requested(task)) {
		cancellation(task);
		return;
	}
	long identity = syscall(SYS_gettid);
	assert(identity != owner);
	atomic_store(&worker_ids[frame->identity - 2], identity);
	atomic_fetch_or(&entered, 1u << (frame->identity - 2));
	struct timespec start, now, delay = {.tv_nsec = 1000000};
	assert(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
	while (atomic_load(&entered) != 3) {
		assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0 && now.tv_sec - start.tv_sec < 2);
		assert(nanosleep(&delay, NULL) == 0);
	}
	/* Keep both native regions active past actual file completion observation. */
	delay.tv_nsec = 20000000;
	assert(nanosleep(&delay, NULL) == 0);
	frame->value = frame->identity * 17 + 5;
	astra_async_complete(task, frame->mode == 2 && frame->identity == 2 ? ASTRA_ASYNC_EXCEPTION : ASTRA_ASYNC_SUCCESS,
	                     frame->mode == 2 && frame->identity == 2 ? &exception_identity : NULL);
}

static void file_io(AstraAsyncTask *task) {
	Frame *frame = astra_async_data(task);
	assert(syscall(SYS_gettid) == owner);
	if (astra_async_cancel_requested(task)) {
		cancellation(task);
		return;
	}
	if (astra_async_pc(task) == 0) {
		astra_async_set_pc(task, 1);
		assert(astra_async_linux_payload(task, frame->payload));
		return;
	}
	assert(astra_async_linux_delay_result(task, 1) == 0);
	assert(astra_linux_payload_count(frame->payload) == 67);
	for (int i = 0; i < 67; ++i)
		assert(astra_linux_payload_byte(frame->payload, i + 3) == ((i + 11) * 17 + 53) % 256);
	astra_async_complete(task, ASTRA_ASYNC_SUCCESS, NULL);
}

static AstraAsyncTask *create(AstraAsyncTask *parent, AstraAsyncResume resume, int identity, int mode) {
	AstraAsyncTask *task = astra_async_new(sizeof(Frame), _Alignof(Frame), resume, dispose, parent);
	*(Frame *)astra_async_data(task) = (Frame){.identity = identity, .mode = mode};
	return task;
}

static void control(AstraAsyncTask *task) {
	Frame *frame = astra_async_data(task);
	assert(syscall(SYS_gettid) == owner);
	if (astra_async_cancel_requested(task)) {
		astra_async_linux_test_transport(io_executor, 0, 0);
		cancellation(task);
		return;
	}
	uint32_t pc = astra_async_pc(task);
	if (pc == 0) {
		frame->children[0] = create(task, file_io, 1, frame->mode);
		((Frame *)astra_async_data(frame->children[0]))->payload = frame->payload;
		assert(astra_async_start(io_executor, frame->children[0], task) == ASTRA_ASYNC_ADMITTED);
		for (int i = 0; i < 2; ++i) {
			frame->children[i + 1] = create(task, compute, i + 2, frame->mode);
			assert(astra_async_bridge_start(frame->targets[i], frame->children[i + 1], task) == ASTRA_ASYNC_ADMITTED);
			assert(astra_async_bridge_start(frame->targets[1 - i], frame->children[i + 1], task) == ASTRA_ASYNC_ASSOCIATION);
		}
		astra_async_set_pc(task, 1);
		assert(astra_async_wait(task, frame->children[0], 0) == ASTRA_ASYNC_ADMITTED);
		return;
	}
	if (pc == 1) {
		assert(astra_async_release_wait(task, 1) == ASTRA_ASYNC_SUCCESS);
		assert(atomic_load(&completed) == 1 && atomic_load(&retired) == 2);
	} else {
		AstraAsyncTask *child = astra_async_waited(task);
		assert(((Frame *)astra_async_data(child))->value == (int)pc * 17 + 5);
		int phase = astra_async_phase(child);
		if (frame->mode == 2 && pc == 2)
			assert(phase == ASTRA_ASYNC_EXCEPTION && astra_async_exception(child) == &exception_identity);
		else
			assert(phase == ASTRA_ASYNC_SUCCESS);
		AstraAsyncToken old = astra_async_token(child);
		assert(astra_async_release_wait(task, 1) == phase);
		assert(!astra_async_wake(frame->targets[pc - 2], old));
	}
	if (pc < 3) {
		astra_async_set_pc(task, pc + 1);
		assert(astra_async_bridge_wait(task, frame->children[pc], frame->targets[pc - 1], 0) == ASTRA_ASYNC_ADMITTED);
	} else
		astra_async_complete(task, ASTRA_ASYNC_SUCCESS, NULL);
}

void astra_payload_test_submitted(void) {
	assert(atomic_fetch_add(&submitted, 1) == 0);
}

void astra_payload_test_completed(uint64_t target, uint64_t cancel, int result, int cancel_result, int cancel_seen) {
	assert(target && cancel && target != cancel && (result == 67 || result == -ECANCELED));
	if (cancel_seen) assert(cancel_result == 0 || cancel_result == -ENOENT || cancel_result == -EALREADY);
	assert(atomic_fetch_add(&completed, 1) == 0);
}

static void *cancel_from_foreign_thread(void *unused) {
	(void)unused;
	struct timespec start, now, delay = {.tv_nsec = 1000000};
	assert(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
	while (!atomic_load(&submitted) || atomic_load(&entered) != 3) {
		assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0 && now.tv_sec - start.tv_sec < 2);
		assert(nanosleep(&delay, NULL) == 0);
	}
	assert(astra_async_request_shutdown(io_executor) == 1);
	return NULL;
}

static void await_kernel_retirement(long identity) {
	assert(identity > 0 && identity != owner);
	char path[128];
	assert(snprintf(path, sizeof(path), "/proc/self/task/%ld", identity) > 0);
	struct timespec start, now, delay = {.tv_nsec = 1000000};
	assert(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
	struct stat state;
	while (stat(path, &state) == 0) {
		assert(clock_gettime(CLOCK_MONOTONIC, &now) == 0 && now.tv_sec - start.tv_sec < 2);
		assert(nanosleep(&delay, NULL) == 0);
	}
	assert(errno == ENOENT);
}

int main(int argc, char **argv) {
	assert(argc == 2);
	owner = syscall(SYS_gettid);
	int fd = open(argv[1], O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
	assert(fd >= 0);
	unsigned char input[256];
	for (unsigned i = 0; i < sizeof(input); ++i)
		input[i] = (unsigned char)(i * 17 + 53);
	assert(write(fd, input, sizeof(input)) == (ssize_t)sizeof(input) && close(fd) == 0);
	/* A compiled provider requirement rejects admission before body access. */
	AstraAsyncExecutor *wrong_provider = astra_async_threaded_open(1);
	AstraAsyncTask *wrong_task = create(NULL, control, 4, 0);
	assert(wrong_provider && wrong_task);
	astra_async_require_provider(wrong_task, 1);
	assert(astra_async_start(wrong_provider, wrong_task, NULL) == ASTRA_ASYNC_ASSOCIATION);
	astra_async_drop(wrong_task);
	astra_async_close(wrong_provider);
	for (int mode = 0; mode < 3; ++mode) {
		atomic_store(&entered, 0);
		atomic_store(&retired, 0);
		atomic_store(&submitted, 0);
		atomic_store(&completed, 0);
		io_executor = astra_async_linux_open(8);
		AstraAsyncExecutor *targets[2] = {astra_async_threaded_open(1), astra_async_threaded_open(1)};
		assert(io_executor && targets[0] && targets[1]);
		AstraLinuxPayload *payload = astra_linux_payload_open((const unsigned char *)argv[1], (int)strlen(argv[1]), 97, 0);
		assert(payload && astra_linux_payload_configure(payload, 3, 67, 11) == 0);
		root_task = create(NULL, control, 0, mode);
		Frame *frame = astra_async_data(root_task);
		frame->payload = payload;
		for (int i = 0; i < 2; ++i)
			frame->targets[i] = targets[i];
		pthread_t cancellation_thread;
		if (mode == 1) {
			astra_async_linux_test_transport(io_executor, 0, 1);
			assert(pthread_create(&cancellation_thread, NULL, cancel_from_foreign_thread, NULL) == 0);
		}
		void *exception = NULL;
		assert(astra_async_run(io_executor, root_task, &exception) == (mode == 1 ? ASTRA_ASYNC_CANCELLED : ASTRA_ASYNC_SUCCESS) && exception == NULL);
		if (mode == 1) assert(pthread_join(cancellation_thread, NULL) == 0);
		assert(atomic_load(&retired) == 15 && atomic_load(&entered) == 3 && atomic_load(&completed) == 1);
		for (int i = 0; i < 2; ++i) {
			astra_async_close(targets[i]);
			await_kernel_retirement(atomic_load(&worker_ids[i]));
		}
		assert(atomic_load(&worker_ids[0]) != atomic_load(&worker_ids[1]));
		astra_linux_payload_close(payload);
		astra_async_close(io_executor);
	}
	assert(unlink(argv[1]) == 0);
	puts("bridge protocol: two worker instances, actual file CQEs, success/error/foreign cancellation, exact retirement and joined shutdown");
	return 0;
}
