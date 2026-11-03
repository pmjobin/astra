/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "linux.h"
#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <liburing.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
static unsigned turns, destroys;
static int deny_setup;
static int deny_probe;
extern int __real_io_uring_queue_init_params(unsigned entries, struct io_uring *ring, struct io_uring_params *params);

int __wrap_io_uring_queue_init_params(unsigned entries, struct io_uring *ring, struct io_uring_params *params) {
	return deny_setup ? -EPERM : __real_io_uring_queue_init_params(entries, ring, params);
}

extern int __real_io_uring_register_probe(struct io_uring *ring, struct io_uring_probe *probe, unsigned count);

int __wrap_io_uring_register_probe(struct io_uring *ring, struct io_uring_probe *probe, unsigned count) {
	return deny_probe ? -EACCES : __real_io_uring_register_probe(ring, probe, count);
}

static unsigned fds(void) {
	DIR *directory = opendir("/proc/self/fd");
	assert(directory != NULL);
	unsigned count = 0;
	struct dirent *entry;
	while ((entry = readdir(directory)) != NULL) {
		if (entry->d_name[0] != '.') {
			count++;
		}
	}
	closedir(directory);
	return count;
}

static unsigned ring_maps(void) {
	FILE *stream = fopen("/proc/self/maps", "r");
	assert(stream != NULL);
	char line[1024];
	unsigned count = 0;
	while (fgets(line, sizeof(line), stream) != NULL) {
		if (strstr(line, "io_uring") != NULL) {
			count++;
		}
	}
	fclose(stream);
	return count;
}

static void destroy(AstraAsyncTask *task, int discard) {
	(void)task;
	(void)discard;
	destroys++;
}

static void resume(AstraAsyncTask *task) {
	turns++;
	if (astra_async_cancel_requested(task)) {
		if (astra_async_cancel_scope(task)) {
			astra_async_complete(task, ASTRA_ASYNC_CANCELLED, NULL);
		}
		return;
	}
	if (astra_async_pc(task) == 0) {
		astra_async_set_pc(task, 1);
		assert(astra_async_linux_delay_ms(task, 1));
		return;
	}
	assert(astra_async_linux_delay_result(task, 1) == 0);
	astra_async_complete(task, ASTRA_ASYNC_SUCCESS, NULL);
}

static AstraAsyncTask *root(AstraAsyncExecutor *executor) {
	AstraAsyncTask *task = astra_async_new(1, 1, resume, destroy, NULL);
	assert(astra_async_start(executor, task, NULL) == ASTRA_ASYNC_ADMITTED);
	return task;
}

static void retire(AstraAsyncExecutor *executor, AstraAsyncTask *task, int phase) {
	astra_async_begin_shutdown(executor);
	assert(astra_async_shutdown_complete(executor));
	assert(astra_async_observe_root(executor, task, phase == ASTRA_ASYNC_SUCCESS) == phase);
	assert(astra_async_finish_shutdown(executor));
	astra_async_close(executor);
}

int main(void) {
	alarm(15);
	unsigned baseline_fds = fds(), baseline_maps = ring_maps();
	deny_setup = 1;
	for (unsigned i = 0; i < 8; i++) {
		assert(astra_async_linux_open(1) == NULL);
		AstraAsyncLinuxFailure failure = astra_async_linux_last_failure();
		assert(failure.operation == ASTRA_LINUX_SETUP && failure.error == EPERM);
		assert(fds() == baseline_fds && ring_maps() == baseline_maps);
	}
	deny_setup = 0;
	deny_probe = 1;
	for (unsigned i = 0; i < 8; i++) {
		assert(astra_async_linux_open(1) == NULL);
		AstraAsyncLinuxFailure failure = astra_async_linux_last_failure();
		assert(failure.operation == ASTRA_LINUX_PROBE && failure.error == EACCES);
		assert(fds() == baseline_fds && ring_maps() == baseline_maps);
	}
	deny_probe = 0;
	for (unsigned i = 0; i < 16; i++) {
		AstraAsyncExecutor *executor = astra_async_linux_open(1);
		assert(executor != NULL);
		assert(fds() == baseline_fds + 1 && ring_maps() > baseline_maps);
		AstraAsyncTask *task = root(executor);
		astra_async_pump(executor, 1);
		if (i % 2) {
			astra_async_linux_test_transport(executor, 0, 1);
			struct timespec elapsed = {0, 10000000};
			assert(nanosleep(&elapsed, NULL) == 0);
			unsigned before = destroys;
			astra_async_cancel(task);
			astra_async_pump(executor, 1);
			assert(destroys == before);
			AstraAsyncLinuxSnapshot record;
			assert(astra_async_linux_test_snapshot(executor, 0, &record) && record.cancel_prepared && !record.target_seen && !record.cancel_seen);
			astra_async_linux_test_transport(executor, 0, 0);
		}
		while (astra_async_phase(task) < ASTRA_ASYNC_SUCCESS) {
			astra_async_linux_wait(executor);
			astra_async_pump(executor, 1);
		}
		AstraAsyncLinuxSnapshot record;
		assert(astra_async_linux_test_record(executor, 0, &record));
		assert(!record.active && record.target_seen && record.target_result == -ETIME);
		if (i % 2) {
			assert(record.cancel_seen && record.cancel_result == -ENOENT);
		}
		printf("REAL queued trial=%u target=%llu result=%d cancel=%llu observed=%u result=%d token=%llu/%u/%llu\n", i, (unsigned long long)record.target, record.target_result, (unsigned long long)record.cancel, record.cancel_seen, record.cancel_result, (unsigned long long)record.token.executor, record.token.slot, (unsigned long long)record.token.generation);
		retire(executor, task, i % 2 ? ASTRA_ASYNC_CANCELLED : ASTRA_ASYNC_SUCCESS);
		assert(fds() == baseline_fds && ring_maps() == baseline_maps);
	}
	assert(destroys == 16);
	pid_t child = fork();
	assert(child >= 0);
	if (child == 0) {
		AstraAsyncExecutor *executor = astra_async_linux_open(1);
		assert(executor != NULL);
		astra_async_linux_test_fake(executor);
		(void)root(executor);
		astra_async_linux_test_submit(executor, -EIO);
		astra_async_pump(executor, 1);
		_Exit(99);
	}
	int status;
	assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 120);
	printf("REAL fd/map restoration: baseline fd=%u ring maps=%u, 16 cycles/16 frame destroys; INJECTED 8 setup EPERM, 8 post-mapping probe EACCES and fatal non-unwinding submit EIO\n", baseline_fds, baseline_maps);
	return 0;
}
