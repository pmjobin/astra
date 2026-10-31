/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "linux.h"
#include "provider.h"
#include <errno.h>
#include <fcntl.h>
#include <liburing.h>
#include <limits.h>
#include <poll.h>
#include <stdio.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/utsname.h>
#include <sys/eventfd.h>
#include <sys/syscall.h>
#include <unistd.h>

#if !defined(__linux__) || !defined(__x86_64__) || ULONG_MAX != UINT64_MAX
#error L1 requires GNU LP64 x86-64 Linux
#endif
#if IO_URING_VERSION_MAJOR < 2 || (IO_URING_VERSION_MAJOR == 2 && IO_URING_VERSION_MINOR < 15)
#error L1 requires matching liburing headers and library at least 2.15
#endif
_Static_assert(sizeof(struct io_uring_sqe) == 64 && sizeof(struct io_uring_cqe) == 16, "L1 ring element profile");

struct AstraLinuxPayload {
	int fd;
	unsigned char *bytes;
	int capacity;
	int offset;
	int count;
	int result;
	int error;
	int writing;
	int active;
	int64_t file_offset;
};
#ifdef ASTRA_ASYNC_LINUX_TEST_PROTOCOL
/* Optional receipt observers receive copied identities/results, never buffer
 * addresses. They cannot replace production CQ ingress or release authority. */
void astra_payload_test_submitted(void) __attribute__((weak));
void astra_payload_test_closed(void) __attribute__((weak));
void astra_payload_test_completed(uint64_t target, uint64_t cancel, int target_result, int cancel_result, int cancel_seen) __attribute__((weak));
#endif

/* Finite unique resource; all accessor/mutation/close paths fail closed while
 * the kernel may still use the buffer or fd. OOM keeps the existing abort policy. */
AstraLinuxPayload *astra_linux_payload_open(const unsigned char *path, int length, int capacity, int writing) {
	if (!path || length <= 0 || length > 4096 || memchr(path, 0, (size_t)length) || capacity < 0 || capacity > 1048576 || (writing != 0 && writing != 1)) {
		return NULL;
	}
	char *name = malloc((size_t)length + 1);
	if (!name) {
		abort();
	}
	memcpy(name, path, (size_t)length);
	name[length] = 0;
	int fd = open(name, (writing ? O_WRONLY | O_CREAT | O_TRUNC : O_RDONLY) | O_CLOEXEC, 0600);
	free(name);
	if (fd < 0) {
		return NULL;
	}
	AstraLinuxPayload *payload = calloc(1, sizeof(*payload));
	if (!payload) {
		close(fd);
		abort();
	}
	payload->bytes = calloc(capacity ? (size_t)capacity : 1, 1);
	if (!payload->bytes) {
		close(fd);
		free(payload);
		abort();
	}
	payload->fd = fd;
	payload->capacity = capacity;
	payload->count = capacity;
	payload->writing = writing;
	return payload;
}
static void payload_idle(AstraLinuxPayload *payload) {
	if (!payload || payload->active) {
		fprintf(stderr, "Astra payload integrity stop: owner is null or still in flight\n");
		_Exit(121);
	}
}
void astra_linux_payload_close(AstraLinuxPayload *payload) {
	if (!payload) {
		return;
	}
	payload_idle(payload);
	int fd = payload->fd;
	payload->fd = -1;
	free(payload->bytes);
	free(payload); /* Linux close is never retried after EINTR. */
	if (fd >= 0) {
		(void)close(fd);
	}
#ifdef ASTRA_ASYNC_LINUX_TEST_PROTOCOL
	if (astra_payload_test_closed) {
		astra_payload_test_closed();
	}
#endif
}
int astra_linux_payload_finish(AstraLinuxPayload *payload) {
	payload_idle(payload);
	int fd = payload->fd;
	payload->fd = -1;
	return fd < 0 ? -EBADF : close(fd) == 0 ? 0
	                                        : -errno;
}
int astra_linux_payload_configure(AstraLinuxPayload *payload, int offset, int count, int64_t file_offset) {
	payload_idle(payload);
	if (offset < 0 || count < 0 || offset > payload->capacity || count > payload->capacity - offset || file_offset < 0 || file_offset > INT64_MAX - count) {
		return -EINVAL;
	}
	payload->offset = offset;
	payload->count = count;
	payload->file_offset = file_offset;
	/* A new requested range is not evidence that its bytes have been read. */
	payload->result = 0;
	payload->error = 0;
	return 0;
}
int astra_linux_payload_byte(AstraLinuxPayload *payload, int index) {
	payload_idle(payload);
	if (index < 0 || index >= payload->capacity || (!payload->writing && (index < payload->offset || index - payload->offset >= payload->result))) {
		return -EINVAL;
	}
	return payload->bytes[index];
}
int astra_linux_payload_set(AstraLinuxPayload *payload, int index, int byte) {
	payload_idle(payload);
	if (!payload->writing || index < 0 || index >= payload->capacity || byte < 0 || byte > 255) {
		return -EINVAL;
	}
	payload->bytes[index] = (unsigned char)byte;
	return 0;
}
int astra_linux_payload_count(AstraLinuxPayload *payload) {
	payload_idle(payload);
	return payload->result;
}
int astra_linux_payload_error(AstraLinuxPayload *payload) {
	payload_idle(payload);
	return payload->error;
}

typedef struct LinuxTimer {
	AstraLinuxPayload *payload;
	AstraAsyncToken token;
	uint64_t generation;
	uint64_t target;
	uint64_t cancel;
	uint64_t ns;
	uint64_t target_sequence;
	uint64_t cancel_sequence;
	uint32_t pc;
	int target_result;
	int cancel_result;
	unsigned active : 1;
	unsigned prepared : 1;
	unsigned exposed : 1;
	unsigned consumed : 1;
	unsigned cancellation : 1;
	unsigned cancel_prepared : 1;
	unsigned cancel_exposed : 1;
	unsigned cancel_consumed : 1;
	unsigned target_seen : 1;
	unsigned cancel_seen : 1;
} LinuxTimer;

typedef struct LinuxState {
	struct io_uring ring;
	long owner;
	int wake_fd;
	LinuxTimer timers[16];
	uint32_t capacity;
	uint32_t active;
	uint64_t prepared_count;
	int payload_supported;
#ifdef ASTRA_ASYNC_LINUX_TEST_PROTOCOL
	int injected_submit;
	int has_injected_submit;
	int fake;
	int hold_submit;
	unsigned fake_head;
	unsigned fake_tail;
	unsigned fake_published;
	struct io_uring_sqe fake_sq[32];
	int hold_completions;
#endif
} LinuxState;

static const AstraAsyncProvider linux_provider;
static _Thread_local AstraAsyncLinuxFailure last_failure;
/* Single-threaded L1: process-unique IDs additionally reject cross-ring ingress. */
static _Atomic uint64_t next_operation_id = 1;
static uint64_t reserve_operation_ids(void) {
	uint64_t current = atomic_load_explicit(&next_operation_id, memory_order_relaxed);
	while (current != 0 && current <= UINT64_MAX - 2) {
		if (atomic_compare_exchange_weak_explicit(&next_operation_id, &current, current + 2, memory_order_relaxed, memory_order_relaxed)) return current;
	}
	return 0;
}
static LinuxState *state_of(AstraAsyncExecutor *executor) {
	LinuxState *state = astra_async_provider_state(executor, &linux_provider);
	if (state->owner != syscall(SYS_gettid)) {
		fprintf(stderr, "Astra Linux async integrity stop: ring operation requires its creating owner\n");
		_Exit(120);
	}
	return state;
}
static int same_token(AstraAsyncToken a, AstraAsyncToken b) {
	return a.slot == b.slot && a.generation == b.generation && a.executor == b.executor;
}
static int failure(int operation, int error, uint64_t id) {
	last_failure = (AstraAsyncLinuxFailure){operation, error, id};
	return 0;
}
static void fatal(int operation, int error, uint64_t id) {
	failure(operation, error, id);
	fprintf(stderr, "Astra Linux async integrity stop: operation=%d errno=%d id=%llu\n", operation, error, (unsigned long long)id);
	fflush(stderr);
	_Exit(120);
}
AstraAsyncLinuxFailure astra_async_linux_last_failure(void) {
	return last_failure;
}

static void finish(AstraAsyncExecutor *executor, LinuxTimer *timer) {
	if (!timer->target_seen || (timer->cancel_prepared && !timer->cancel_seen)) {
		return;
	}
	int error = (timer->payload ? timer->target_result >= 0 : timer->target_result == -ETIME) || (timer->target_result == -ECANCELED && timer->cancellation) ? 0 : -timer->target_result;
	int operation = ASTRA_LINUX_TARGET;
	uint64_t id = timer->target;
	if (timer->cancel_seen && timer->cancel_result != 0 && timer->cancel_result != -ENOENT && timer->cancel_result != -EALREADY) {
		error = -timer->cancel_result;
		operation = ASTRA_LINUX_CANCEL;
		id = timer->cancel;
	}
	if (error != 0) {
		failure(operation, error, id);
	}
	if (timer->payload) {
		/* Only this observed, fully drained transition publishes access rights.
		 * A successful cancel command alone cannot clear active. */
		timer->payload->result = timer->target_result >= 0 ? timer->target_result : 0;
		timer->payload->error = timer->target_result < 0 ? -timer->target_result : 0;
		timer->payload->active = 0;
#ifdef ASTRA_ASYNC_LINUX_TEST_PROTOCOL
		if (astra_payload_test_completed) {
			astra_payload_test_completed(timer->target, timer->cancel, timer->target_result, timer->cancel_result, timer->cancel_seen);
		}
#endif
	}
	/* Both identities remain live until the corresponding events are observed. */
	if (!astra_async_provider_complete(executor, timer->token, timer->pc, error)) {
		fatal(ASTRA_LINUX_DECODE, EPROTO, timer->target);
	}
	timer->active = 0;
	LinuxState *state = state_of(executor);
	if (state->active == 0) {
		fatal(ASTRA_LINUX_CREDITS, EPROTO, timer->target);
	}
	state->active--;
}

/* The production ingress checks identity, role and evidence before any mutation. */
static int decode(AstraAsyncExecutor *executor, uint64_t id, int result, unsigned flags) {
	LinuxState *state = state_of(executor);
	if (id == 0 || flags != 0 || result == INT_MIN) {
		return failure(ASTRA_LINUX_DECODE, EPROTO, id);
	}
	for (uint32_t i = 0; i < state->capacity; i++) {
		LinuxTimer *timer = &state->timers[i];
		if (!timer->active) {
			continue;
		}
		if (id == timer->target) {
			if (!timer->prepared || !timer->exposed || timer->target_seen || (timer->payload ? result > timer->payload->count : result >= 0)) {
				return failure(ASTRA_LINUX_DECODE, EPROTO, id);
			}
			timer->target_result = result;
			timer->target_seen = 1;
			timer->consumed = 1; /* A valid CQE independently proves consumption. */
			finish(executor, timer);
			return 1;
		}
		if (id == timer->cancel) {
			if (!timer->cancel_prepared || !timer->cancel_exposed || timer->cancel_seen || result > 0) {
				return failure(ASTRA_LINUX_DECODE, EPROTO, id);
			}
			timer->cancel_result = result;
			timer->cancel_seen = 1;
			timer->cancel_consumed = 1;
			finish(executor, timer);
			return 1;
		}
	}
	return failure(ASTRA_LINUX_DECODE, EPROTO, id);
}

static void cancel_timer(AstraAsyncExecutor *executor, AstraAsyncToken token) {
	LinuxState *state = state_of(executor);
	for (uint32_t i = 0; i < state->capacity; i++) {
		LinuxTimer *timer = &state->timers[i];
		if (!timer->active || !same_token(timer->token, token)) {
			continue;
		}
		timer->cancellation = 1;
		if (!timer->prepared) {
			/* Private intent: no SQE has been acquired or made visible. */
			timer->target_seen = 1;
			timer->target_result = -ECANCELED;
			finish(executor, timer);
		}
		return;
	}
}

static struct io_uring_sqe *get_sqe(LinuxState *state) {
#ifdef ASTRA_ASYNC_LINUX_TEST_PROTOCOL
	if (state->fake) {
		if (state->fake_tail - state->fake_head == 32) {
			return NULL;
		}
		return &state->fake_sq[state->fake_tail++ % 32];
	}
#endif
	return io_uring_get_sqe(&state->ring);
}
static void prepare(LinuxState *state) {
	for (uint32_t i = 0; i < state->capacity; i++) {
		LinuxTimer *timer = &state->timers[i];
		if (!timer->active) {
			continue;
		}
		if (!timer->prepared) {
			struct io_uring_sqe *sqe = get_sqe(state);
			if (sqe == NULL) {
				return;
			}
			if (timer->payload) {
				AstraLinuxPayload *p = timer->payload;
				if (p->writing) {
					io_uring_prep_write(sqe, p->fd, p->bytes + p->offset, (unsigned)p->count, (uint64_t)p->file_offset);
				} else {
					io_uring_prep_read(sqe, p->fd, p->bytes + p->offset, (unsigned)p->count, (uint64_t)p->file_offset);
				}
			} else {
				io_uring_prep_timeout(sqe, NULL, 0, IORING_TIMEOUT_IMMEDIATE_ARG);
				sqe->addr = timer->ns;
			}
			io_uring_sqe_set_data64(sqe, timer->target);
			timer->prepared = 1;
			timer->target_sequence = ++state->prepared_count;
		}
		if (timer->cancellation && !timer->cancel_prepared && !timer->target_seen) {
			struct io_uring_sqe *sqe = get_sqe(state);
			if (sqe == NULL) {
				return;
			}
			io_uring_prep_cancel64(sqe, timer->target, 0);
			io_uring_sqe_set_data64(sqe, timer->cancel);
			timer->cancel_prepared = 1;
			timer->cancel_sequence = ++state->prepared_count;
		}
	}
}

static int enter(LinuxState *state, int wait) {
#ifdef ASTRA_ASYNC_LINUX_TEST_PROTOCOL
	if (state->fake && !(state->hold_submit && !state->has_injected_submit)) {
		state->fake_published = state->fake_tail;
	}
	if (state->has_injected_submit && (!state->fake || state->fake_tail != state->fake_head)) {
		int result = state->injected_submit;
		state->has_injected_submit = 0;
		if (state->fake && result > 0) {
			unsigned pending = state->fake_tail - state->fake_head;
			if ((unsigned)result > pending) {
				abort();
			}
			state->fake_head += (unsigned)result;
		}
		return result;
	}
	if (state->fake && state->hold_submit) {
		return 0;
	}
	if (state->fake) {
		int result = (int)(state->fake_tail - state->fake_head);
		state->fake_head = state->fake_tail;
		return result;
	}
#endif
	/* liburing owns tail publication. Never rebuild SQEs after a short enter. */
	return wait ? io_uring_submit_and_wait(&state->ring, 1) : io_uring_submit(&state->ring);
}
static int submit(LinuxState *state, int wait) {
	int result = enter(state, wait);
	/* Private helper head records flush; sq_ready uses liburing's kernel ordering. */
	unsigned unpublished = state->ring.sq.sqe_tail - state->ring.sq.sqe_head;
	unsigned pending = io_uring_sq_ready(&state->ring);
#ifdef ASTRA_ASYNC_LINUX_TEST_PROTOCOL
	if (state->fake) {
		unpublished = state->fake_tail - state->fake_published;
		pending = state->fake_tail - state->fake_head;
	}
#endif
	if (pending > 32 || unpublished > pending || pending > state->prepared_count) {
		fatal(ASTRA_LINUX_CREDITS, EPROTO, 0);
	}
	uint64_t published = state->prepared_count - unpublished, consumed = state->prepared_count - pending;
	for (uint32_t i = 0; i < state->capacity; i++) {
		LinuxTimer *timer = &state->timers[i];
		if (!timer->active) {
			continue;
		}
		if (timer->prepared) {
			timer->exposed |= timer->target_sequence <= published;
			timer->consumed |= timer->target_sequence <= consumed;
		}
		if (timer->cancel_prepared) {
			timer->cancel_exposed |= timer->cancel_sequence <= published;
			timer->cancel_consumed |= timer->cancel_sequence <= consumed;
		}
	}
	return result;
}
static void completions(AstraAsyncExecutor *executor) {
	LinuxState *state = state_of(executor);
#ifdef ASTRA_ASYNC_LINUX_TEST_PROTOCOL
	if (state->fake || state->hold_completions) {
		return;
	}
#endif
	struct io_uring_cqe *batch[32];
	unsigned count = io_uring_peek_batch_cqe(&state->ring, batch, 32);
	for (unsigned i = 0; i < count; i++) {
		uint64_t id = batch[i]->user_data;
		int result = batch[i]->res;
		unsigned flags = batch[i]->flags;
		if (!decode(executor, id, result, flags)) {
			fatal(ASTRA_LINUX_DECODE, EPROTO, id);
		}
		io_uring_cqe_seen(&state->ring, batch[i]);
	}
}
static void transport_stop(AstraAsyncExecutor *executor, int error, uint64_t id) {
	LinuxState *state = state_of(executor);
	/* Preserve exposed identities; attempt only two nonwaiting drain batches. */
	for (uint32_t i = 0; i < state->capacity; i++) {
		if (state->timers[i].active) {
			state->timers[i].cancellation = 1;
		}
	}
	for (unsigned attempt = 0; attempt < 2; attempt++) {
		prepare(state);
		(void)submit(state, 0);
		completions(executor);
	}
	fprintf(stderr, "Astra Linux bounded drain: retained operations=%u; no user dispatch or unwind\n", state->active);
	fatal(ASTRA_LINUX_SUBMIT, error, id);
}
static void notify_owner(void *opaque) {
	LinuxState *state = opaque;
	uint64_t one = 1;
	ssize_t count;
	do {
		count = write(state->wake_fd, &one, sizeof(one));
	} while (count < 0 && errno == EINTR);
	if (count != (ssize_t)sizeof(one) && !(count < 0 && errno == EAGAIN)) {
		fatal(ASTRA_LINUX_CREDITS, count < 0 ? errno : EIO, 0);
	}
}
static void pending_cancels(AstraAsyncExecutor *executor) {
	AstraAsyncToken token;
	while (astra_async_provider_take_cancel(executor, &token))
		cancel_timer(executor, token);
}
static void service(AstraAsyncExecutor *executor, int wait) {
	LinuxState *state = state_of(executor);
	pending_cancels(executor);
	prepare(state);
	int code = submit(state, 0);
	if (code < 0 && code != -EINTR && code != -EAGAIN && code != -EBUSY) {
		transport_stop(executor, -code, 0);
	}
	completions(executor);
	if (wait && !astra_async_provider_ready(executor) && (state->active != 0 || state->wake_fd >= 0)) {
		if (state->wake_fd >= 0) {
			/* CQ readiness and cross-executor publications are independent wake
			 * sources. A worker never enters/submits/drains the SINGLE_ISSUER ring.
			 * The bounded poll timeout is a transport retry backstop; eventfd is
			 * the publication notification, including when no I/O is active. */
			struct pollfd sources[2] = {{state->ring.ring_fd, POLLIN, 0}, {state->wake_fd, POLLIN, 0}};
			int ready;
			do {
				ready = poll(sources, 2, 100);
			} while (ready < 0 && errno == EINTR);
			if (ready < 0 || (sources[0].revents | sources[1].revents) & (POLLERR | POLLHUP | POLLNVAL)) {
				fatal(ASTRA_LINUX_CREDITS, ready < 0 ? errno : EIO, 0);
			}
			uint64_t value;
			ssize_t count;
			do {
				count = read(state->wake_fd, &value, sizeof(value));
			} while (count < 0 && errno == EINTR);
			if (count != (ssize_t)sizeof(value) && !(count < 0 && errno == EAGAIN)) {
				fatal(ASTRA_LINUX_CREDITS, count < 0 ? errno : EIO, 0);
			}
			pending_cancels(executor);
			prepare(state);
			code = submit(state, 0);
		} else {
			code = submit(state, 1);
		}
		if (code < 0 && code != -EINTR && code != -EAGAIN && code != -EBUSY) {
			transport_stop(executor, -code, 0);
		}
		completions(executor);
	}
}
static void close_ring(AstraAsyncExecutor *executor) {
	LinuxState *state = state_of(executor);
	if (state->active != 0 || io_uring_sq_ready(&state->ring) != 0 || io_uring_cq_ready(&state->ring) != 0) {
		fatal(ASTRA_LINUX_CREDITS, EBUSY, 0);
	}
	astra_async_provider_notify(executor, NULL, NULL);
	io_uring_queue_exit(&state->ring);
	if (state->wake_fd >= 0) {
		(void)close(state->wake_fd);
	}
	free(state);
}
static const AstraAsyncProvider linux_provider = {service, cancel_timer, close_ring};

AstraAsyncExecutor *astra_async_linux_open(uint32_t capacity) {
	last_failure = (AstraAsyncLinuxFailure){0};
	if (capacity < 1 || capacity > 16) {
		failure(ASTRA_LINUX_CAPACITY, EINVAL, 0);
		return NULL;
	}
	struct utsname host;
	unsigned major = 0, minor = 0;
	if (uname(&host) != 0 || sscanf(host.release, "%u.%u", &major, &minor) != 2 || major < 7 || (major == 7 && minor < 2)) {
		failure(ASTRA_LINUX_KERNEL, ENOTSUP, 0);
		return NULL;
	}
	if (io_uring_major_version() != IO_URING_VERSION_MAJOR || io_uring_minor_version() != IO_URING_VERSION_MINOR) {
		failure(ASTRA_LINUX_PROFILE, ENOTSUP, 0);
		return NULL;
	}
	LinuxState *state = calloc(1, sizeof(*state));
	if (state == NULL) {
		abort();
	}
	state->owner = syscall(SYS_gettid);
	state->wake_fd = -1;
	struct io_uring_params p = {0};
	const unsigned flags = IORING_SETUP_CQSIZE | IORING_SETUP_SINGLE_ISSUER | IORING_SETUP_NO_SQARRAY;
	p.flags = flags;
	p.cq_entries = 64;
	int code = io_uring_queue_init_params(32, &state->ring, &p);
	if (code < 0) {
		failure(ASTRA_LINUX_SETUP, -code, 0);
		free(state);
		return NULL;
	}
	if (p.flags != flags || p.sq_entries != 32 || p.cq_entries != 64 || !(p.features & IORING_FEAT_NODROP)) {
		failure(ASTRA_LINUX_PROFILE, ENOTSUP, 0);
		io_uring_queue_exit(&state->ring);
		free(state);
		return NULL;
	}
	/* The convenience probe discards register errno; preserve the exact status. */
	struct io_uring_probe *probe = calloc(1, sizeof(*probe) + 256 * sizeof(struct io_uring_probe_op));
	if (probe == NULL) {
		abort();
	}
	code = io_uring_register_probe(&state->ring, probe, 256);
	if (code < 0 || !io_uring_opcode_supported(probe, IORING_OP_TIMEOUT) || !io_uring_opcode_supported(probe, IORING_OP_ASYNC_CANCEL)) {
		failure(ASTRA_LINUX_PROBE, code < 0 ? -code : ENOTSUP, 0);
		free(probe);
		io_uring_queue_exit(&state->ring);
		free(state);
		return NULL;
	}
	state->payload_supported = io_uring_opcode_supported(probe, IORING_OP_READ) && io_uring_opcode_supported(probe, IORING_OP_WRITE);
	free(probe);
	state->capacity = capacity;
	AstraAsyncExecutor *executor = astra_async_provider_open(capacity, &linux_provider, state);
	if (executor == NULL) {
		failure(ASTRA_LINUX_IDS, EOVERFLOW, 0);
		io_uring_queue_exit(&state->ring);
		free(state);
	} else if (astra_async_concurrent_core()) {
		state->wake_fd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
		if (state->wake_fd < 0) {
			failure(ASTRA_LINUX_SETUP, errno, 0);
			astra_async_close(executor);
			return NULL;
		}
		astra_async_provider_notify(executor, notify_owner, state);
	}
	return executor;
}
static int admit(AstraAsyncTask *task, int64_t milliseconds, AstraLinuxPayload *payload) {
	LinuxState *state = state_of(astra_async_executor(task));
	if (payload && (!state->payload_supported || payload->active)) {
		return failure(ASTRA_LINUX_PROBE, payload->active ? EBUSY : ENOTSUP, 0);
	}
	if (milliseconds < 0 || (uint64_t)milliseconds > UINT64_MAX / 1000000) {
		return failure(ASTRA_LINUX_DURATION, EINVAL, 0);
	}
	if (state->active == state->capacity) {
		return failure(ASTRA_LINUX_CREDITS, ENOSPC, 0);
	}
	uint32_t i;
	for (i = 0; i < state->capacity; i++) {
		if (!state->timers[i].active && state->timers[i].generation != UINT64_MAX) {
			break;
		}
	}
	if (i == state->capacity) {
		return failure(ASTRA_LINUX_IDS, EOVERFLOW, 0);
	}
	uint64_t operation = reserve_operation_ids();
	if (operation == 0) {
		return failure(ASTRA_LINUX_IDS, EOVERFLOW, 0);
	}
	LinuxTimer *timer = &state->timers[i];
	uint64_t generation = timer->generation + 1;
	*timer = (LinuxTimer){.payload = payload, .token = astra_async_token(task), .generation = generation, .target = operation, .cancel = operation + 1, .ns = (uint64_t)milliseconds * 1000000, .pc = astra_async_pc(task), .active = 1};
	if (!astra_async_provider_suspend(task, timer)) {
		timer->active = 0;
		return failure(ASTRA_LINUX_CREDITS, EBUSY, timer->target);
	}
	if (payload) {
		payload->active = 1;
		payload->result = 0;
		payload->error = 0;
	}
#ifdef ASTRA_ASYNC_LINUX_TEST_PROTOCOL
	if (payload && astra_payload_test_submitted) {
		astra_payload_test_submitted();
	}
#endif
	state->active++;
	/* Publish before another ready task runs; admission never dispatches user code. */
	prepare(state);
	int code = submit(state, 0);
	if (code < 0 && code != -EINTR && code != -EAGAIN && code != -EBUSY) {
		transport_stop(astra_async_executor(task), -code, timer->target);
	}
	return 1;
}
int astra_async_linux_delay_ms(AstraAsyncTask *task, int64_t milliseconds) {
	return admit(task, milliseconds, NULL);
}
int astra_async_linux_payload(AstraAsyncTask *task, AstraLinuxPayload *payload) {
	if (!payload) {
		return failure(ASTRA_LINUX_TARGET, EINVAL, 0);
	}
	return admit(task, 0, payload);
}
int astra_async_linux_delay_result(AstraAsyncTask *task, uint32_t pc) {
	state_of(astra_async_executor(task));
	return astra_async_provider_result(task, pc);
}
int astra_async_linux_wait(AstraAsyncExecutor *executor) {
	service(executor, 1);
	return 1;
}

#ifdef ASTRA_ASYNC_LINUX_TEST_PROTOCOL
void astra_linux_payload_test_bad_fd(AstraLinuxPayload *payload) {
	payload_idle(payload);
	if (payload->fd >= 0) {
		(void)close(payload->fd);
	}
	payload->fd = -1;
}
int astra_async_linux_test_record(AstraAsyncExecutor *executor, uint32_t slot, AstraAsyncLinuxSnapshot *out) {
	LinuxState *state = state_of(executor);
	if (slot >= state->capacity || state->timers[slot].generation == 0) {
		return 0;
	}
	LinuxTimer *t = &state->timers[slot];
	*out = (AstraAsyncLinuxSnapshot){t->token, t->target, t->cancel, t->generation, t->pc, t->prepared, t->cancel_prepared, t->target_seen, t->cancel_seen, t->target_result, t->cancel_result, t->active, t->ns, t->exposed, t->consumed, t->cancel_exposed, t->cancel_consumed};
	return 1;
}
int astra_async_linux_test_snapshot(AstraAsyncExecutor *executor, uint32_t slot, AstraAsyncLinuxSnapshot *out) {
	return astra_async_linux_test_record(executor, slot, out) && out->active;
}
int astra_async_linux_test_decode(AstraAsyncExecutor *executor, uint64_t id, int result, unsigned flags) {
	return decode(executor, id, result, flags);
}
void astra_async_linux_test_fake(AstraAsyncExecutor *executor) {
	LinuxState *state = state_of(executor);
	if (state->active != 0 || io_uring_sq_ready(&state->ring) != 0 || io_uring_cq_ready(&state->ring) != 0) {
		abort();
	}
	state->fake = 1;
}
void astra_async_linux_test_submit(AstraAsyncExecutor *executor, int result) {
	LinuxState *state = state_of(executor);
	state->injected_submit = result;
	state->has_injected_submit = 1;
}
void astra_async_linux_test_hold_submit(AstraAsyncExecutor *executor, int hold) {
	LinuxState *state = state_of(executor);
	if (!state->fake) {
		abort();
	}
	state->hold_submit = hold;
}
unsigned astra_async_linux_test_pending(AstraAsyncExecutor *executor) {
	LinuxState *state = state_of(executor);
	if (!state->fake) {
		abort();
	}
	return state->fake_tail - state->fake_head;
}
int astra_async_linux_test_queued(AstraAsyncExecutor *executor, uint64_t id) {
	LinuxState *state = state_of(executor);
	if (state->fake) {
		abort();
	}
	struct io_uring_cqe *batch[64];
	unsigned count = io_uring_peek_batch_cqe(&state->ring, batch, 64);
	for (unsigned i = 0; i < count; i++) {
		if (batch[i]->user_data == id) {
			return 1;
		}
	}
	return 0;
}
void astra_async_linux_test_ids(AstraAsyncExecutor *executor, uint64_t next) {
	LinuxState *state = state_of(executor);
	if (state->active != 0) {
		abort();
	}
	next_operation_id = next;
}
void astra_async_linux_test_transport(AstraAsyncExecutor *executor, int injected_submit, int hold_completions) {
	LinuxState *state = state_of(executor);
	state->injected_submit = injected_submit;
	state->has_injected_submit = injected_submit != 0;
	state->hold_completions = hold_completions;
}
#endif
