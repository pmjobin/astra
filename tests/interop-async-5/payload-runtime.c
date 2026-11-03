/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "linux.h"
#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct Frame {
	AstraLinuxPayload *payload;
	int status;
	int count;
	int turns;
} Frame;

static unsigned destroys;
static int skip_guards;

static void destroy(AstraAsyncTask *task, int discard) {
	(void)discard;
	Frame *f = astra_async_data(task);
	astra_linux_payload_close(f->payload);
	destroys++;
}

static void resume(AstraAsyncTask *task) {
	Frame *f = astra_async_data(task);
	f->turns++;
	if (astra_async_cancel_requested(task)) {
		if (astra_async_cancel_scope(task)) astra_async_complete(task, ASTRA_ASYNC_CANCELLED, NULL);
		return;
	}
	if (!astra_async_pc(task)) {
		astra_async_set_pc(task, 1);
		assert(astra_async_linux_payload(task, f->payload));
		return;
	}
	f->status = astra_async_linux_delay_result(task, 1);
	f->count = astra_linux_payload_count(f->payload);
	astra_async_complete(task, ASTRA_ASYNC_SUCCESS, NULL);
}

static AstraAsyncTask *start(AstraAsyncExecutor *executor, AstraLinuxPayload *payload) {
	AstraAsyncTask *task = astra_async_new(sizeof(Frame), _Alignof(Frame), resume, destroy, NULL);
	*(Frame *)astra_async_data(task) = (Frame){.payload = payload};
	assert(astra_async_start(executor, task, NULL) == ASTRA_ASYNC_ADMITTED);
	return task;
}

static AstraLinuxPayload *open_payload(const char *path, int capacity, int writing) {
	AstraLinuxPayload *p = astra_linux_payload_open((const unsigned char *)path, (int)strlen(path), capacity, writing);
	assert(p);
	return p;
}

static AstraAsyncLinuxSnapshot record(AstraAsyncExecutor *executor) {
	AstraAsyncLinuxSnapshot s;
	assert(astra_async_linux_test_record(executor, 0, &s));
	return s;
}

static void guarded(AstraLinuxPayload *payload, int closing) {
	/* Expected-fatal children inherit live owners. Memory tools run the full
     * terminating parent path separately, without these intentional exits. */
	if (skip_guards) return;
	fflush(NULL);
	pid_t child = fork();
	assert(child >= 0);
	if (!child) {
		if (closing)
			astra_linux_payload_close(payload);
		else
			(void)astra_linux_payload_count(payload);
		_Exit(90);
	}
	int status;
	assert(waitpid(child, &status, 0) == child);
	assert(WIFEXITED(status) && WEXITSTATUS(status) == 121);
}

static int drain(AstraAsyncExecutor *executor, AstraAsyncTask *task) {
	while (astra_async_phase(task) < ASTRA_ASYNC_SUCCESS) {
		astra_async_linux_wait(executor);
		astra_async_pump(executor, 1);
	}
	return astra_async_phase(task);
}

static void finish(AstraAsyncExecutor *executor, AstraAsyncTask *task, int phase) {
	astra_async_begin_shutdown(executor);
	assert(astra_async_shutdown_complete(executor));
	assert(astra_async_observe_root(executor, task, phase == ASTRA_ASYNC_SUCCESS) == phase);
	assert(astra_async_finish_shutdown(executor));
	astra_async_close(executor);
}

static unsigned fds(void) {
	DIR *d = opendir("/proc/self/fd");
	assert(d);
	unsigned count = 0;
	while (readdir(d))
		count++;
	closedir(d);
	return count;
}

static void write_fixture(const char *path, int size) {
	FILE *f = fopen(path, "wb");
	assert(f);
	for (int i = 0; i < size; i++)
		assert(fputc((i * 37) & 255, f) != EOF);
	assert(fclose(f) == 0);
}

static void reads(void) {
	for (int size = 0; size <= 4097; size = size == 0 ? 1 : size == 1 ? 4097
	                                                                  : 4098) {
		write_fixture("read.bin", size);
		for (int offset = 0; offset <= size + 1; offset += size + 1) {
			AstraLinuxPayload *p = open_payload("read.bin", 8192, 0);
			assert(astra_linux_payload_configure(p, 3, 8189, offset) == 0);
			AstraAsyncExecutor *e = astra_async_linux_open(1);
			assert(e);
			astra_async_linux_test_transport(e, 0, 1);
			AstraAsyncTask *t = start(e, p);
			assert(astra_async_pump(e, 1) == 1 && astra_async_phase(t) == ASTRA_ASYNC_WAITING);
			guarded(p, 0);
			guarded(p, 1);
			astra_async_linux_test_transport(e, 0, 0);
			assert(drain(e, t) == ASTRA_ASYNC_SUCCESS);
			Frame *f = astra_async_data(t);
			assert(f->turns == 2 && !f->status && f->count == (offset ? 0 : size));
			for (int i = 0; i < f->count; i++)
				assert(astra_linux_payload_byte(p, 3 + i) == ((i * 37) & 255));
			assert(astra_linux_payload_byte(p, 2) == -EINVAL);
			assert(astra_linux_payload_byte(p, 3 + f->count) == -EINVAL);
			AstraAsyncLinuxSnapshot s = record(e);
			assert(s.target_seen && !s.active && s.target_result == f->count);
			printf("read bytes=%d offset=%d target=%llu result=%d observed=1\n", size, offset, (unsigned long long)s.target, s.target_result);
			assert(astra_linux_payload_configure(p, 100, 1, 0) == 0);
			assert(astra_linux_payload_byte(p, 100) == -EINVAL && astra_linux_payload_count(p) == 0);
			assert(astra_linux_payload_finish(p) == 0);
			finish(e, t, ASTRA_ASYNC_SUCCESS);
		}
	}
}

static void writes_and_errors(void) {
	struct rlimit saved;
	assert(getrlimit(RLIMIT_FSIZE, &saved) == 0);
	struct rlimit bounded = saved;
	bounded.rlim_cur = 4097;
	assert(setrlimit(RLIMIT_FSIZE, &bounded) == 0);
	assert(signal(SIGXFSZ, SIG_IGN) != SIG_ERR);
	AstraLinuxPayload *p = open_payload("short-write.bin", 8192, 1);
	for (int i = 0; i < 8192; i++)
		assert(astra_linux_payload_set(p, i, (i * 37) & 255) == 0);
	AstraAsyncExecutor *e = astra_async_linux_open(1);
	assert(e);
	AstraAsyncTask *t = start(e, p);
	assert(astra_async_pump(e, 1) == 1);
	assert(drain(e, t) == ASTRA_ASYNC_SUCCESS);
	Frame *f = astra_async_data(t);
	assert(!f->status && f->count == 4097);
	printf("actual short write target=%llu result=%d requested=8192\n", (unsigned long long)record(e).target, f->count);
	finish(e, t, ASTRA_ASYNC_SUCCESS);
	assert(setrlimit(RLIMIT_FSIZE, &saved) == 0);
	FILE *written = fopen("short-write.bin", "rb");
	assert(written);
	for (int i = 0; i < 4097; i++)
		assert(fgetc(written) == ((i * 37) & 255));
	assert(fgetc(written) == EOF && fclose(written) == 0);

	p = open_payload("short-write.bin", 8192, 0);
	astra_linux_payload_test_bad_fd(p);
	e = astra_async_linux_open(1);
	assert(e);
	t = start(e, p);
	assert(astra_async_pump(e, 1) == 1);
	assert(drain(e, t) == ASTRA_ASYNC_SUCCESS);
	f = astra_async_data(t);
	assert(f->status == EBADF && astra_linux_payload_error(p) == EBADF && !f->count);
	printf("real invalid-fd target=%llu result=%d checked_status=%d\n", (unsigned long long)record(e).target, record(e).target_result, f->status);
	finish(e, t, ASTRA_ASYNC_SUCCESS);
}

static void cancellations(void) {
	write_fixture("cancel.bin", 8192);
	for (int when = 0; when < 4; when++) {
		AstraLinuxPayload *p = open_payload("cancel.bin", 8192, 0);
		AstraAsyncExecutor *e = astra_async_linux_open(1);
		assert(e);
		if (when == 1 || when == 2) astra_async_linux_test_transport(e, 0, 1);
		AstraAsyncTask *t = start(e, p);
		if (when) assert(astra_async_pump(e, 1) == 1);
		if (when == 2) {
			AstraAsyncLinuxSnapshot s = record(e);
			for (unsigned spin = 0; !astra_async_linux_test_queued(e, s.target); spin++) {
				assert(spin < 10000);
				usleep(100);
			}
			guarded(p, 0); /* CQE exists, but no observed release yet. */
		}
		if (when == 3) assert(drain(e, t) == ASTRA_ASYNC_SUCCESS);
		astra_async_host_cancel(e, t);
		astra_async_linux_test_transport(e, 0, 0);
		int phase = drain(e, t);
		assert(phase == (when == 3 ? ASTRA_ASYNC_SUCCESS : ASTRA_ASYNC_CANCELLED));
		if (when) {
			AstraAsyncLinuxSnapshot s = record(e);
			assert(!s.active && s.target_seen && (!s.cancel_prepared || s.cancel_seen));
			printf("cancel phase=%d target=%llu result=%d cancel=%llu result=%d cancel_seen=%u\n", when,
			       (unsigned long long)s.target, s.target_result, (unsigned long long)s.cancel, s.cancel_result, s.cancel_seen);
		}
		finish(e, t, phase);
	}
	assert(mkfifo("cancel-fifo", 0600) == 0);
	int writer = open("cancel-fifo", O_RDWR | O_CLOEXEC);
	assert(writer >= 0);
	AstraLinuxPayload *p = open_payload("cancel-fifo", 16, 0);
	AstraAsyncExecutor *e = astra_async_linux_open(1);
	assert(e);
	AstraAsyncTask *t = start(e, p);
	assert(astra_async_pump(e, 1) == 1);
	astra_async_host_cancel(e, t);
	assert(drain(e, t) == ASTRA_ASYNC_CANCELLED);
	AstraAsyncLinuxSnapshot s = record(e);
	assert(s.target_seen && s.cancel_seen && s.target_result == -ECANCELED && s.cancel_result == 0 && !s.active);
	printf("blocking file cancel target=%llu result=%d cancel=%llu result=%d both_observed=1\n",
	       (unsigned long long)s.target, s.target_result, (unsigned long long)s.cancel, s.cancel_result);
	finish(e, t, ASTRA_ASYNC_CANCELLED);
	assert(close(writer) == 0 && unlink("cancel-fifo") == 0);
}

static void mutation_protocol(void) {
	AstraLinuxPayload *p = open_payload("cancel.bin", 8, 0);
	AstraAsyncExecutor *e = astra_async_linux_open(1);
	assert(e);
	astra_async_linux_test_fake(e);
	AstraAsyncTask *t = start(e, p);
	assert(astra_async_pump(e, 1) == 1);
	AstraAsyncLinuxSnapshot s = record(e);
	assert(!astra_async_linux_test_decode(e, s.target, 9, 0));
	assert(!astra_async_linux_test_decode(e, s.target, 8, 1));
	assert(!astra_async_linux_test_decode(e, s.target + 3, 0, 0));
	astra_async_host_cancel(e, t);
	astra_async_linux_wait(e);
	s = record(e);
	assert(s.cancel_prepared && s.cancel_exposed);
	assert(astra_async_linux_test_decode(e, s.cancel, 0, 0));
	guarded(p, 0);
	assert(record(e).active && !record(e).target_seen);
	assert(!astra_async_linux_test_decode(e, s.cancel, 0, 0));
	assert(astra_async_linux_test_decode(e, s.target, -ECANCELED, 0));
	assert(!record(e).active && astra_linux_payload_error(p) == ECANCELED);
	assert(!astra_async_linux_test_decode(e, s.target, 0, 0));
	assert(drain(e, t) == ASTRA_ASYNC_CANCELLED);
	finish(e, t, ASTRA_ASYNC_CANCELLED);
	puts("injected protocol controls PASS (separate from real kernel evidence)");
}

int main(int argc, char **argv) {
	skip_guards = argc == 2 && strcmp(argv[1], "--memory") == 0;
	alarm(30);
	unsigned before = fds();
	reads();
	writes_and_errors();
	cancellations();
	mutation_protocol();
	assert(fds() == before && destroys == 14);
	printf("payload runtime PASS: unique destroys=%u fd_count=%u\n", destroys, before);
}
