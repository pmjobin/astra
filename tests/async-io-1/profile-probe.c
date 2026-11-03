/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include <errno.h>
#include <inttypes.h>
#include <liburing.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

static void require(int good) {
	if (!good) {
		fflush(stdout);
		_Exit(99);
	}
}

static uint64_t monotonic_ns(void) {
	struct timespec ts;
	require(clock_gettime(CLOCK_MONOTONIC, &ts) == 0);
	return (uint64_t)ts.tv_sec * 1000000000 + ts.tv_nsec;
}

static void timeout(struct io_uring *ring, uint64_t ns, uint64_t id) {
	struct io_uring_sqe *sqe = io_uring_get_sqe(ring);
	require(sqe != NULL);
	io_uring_prep_timeout(sqe, NULL, 0, IORING_TIMEOUT_IMMEDIATE_ARG);
	sqe->addr = ns;
	io_uring_sqe_set_data64(sqe, id);
	require(sqe->len == 1 && sqe->off == 0 && sqe->timeout_flags == IORING_TIMEOUT_IMMEDIATE_ARG);
	require(io_uring_submit(ring) == 1);
}

static struct io_uring_cqe observe(struct io_uring *ring) {
	struct io_uring_cqe *cqe;
	require(io_uring_wait_cqe(ring, &cqe) == 0);
	struct io_uring_cqe result = *cqe;
	require(result.flags == 0);
	io_uring_cqe_seen(ring, cqe);
	return result;
}

int main(void) {
	alarm(10); /* Probe ceiling; never teardown unknown in-flight work. */
	setbuf(stdout, NULL);
	struct io_uring ring;
	struct io_uring_params p = {0};
	const unsigned flags = IORING_SETUP_CQSIZE | IORING_SETUP_SINGLE_ISSUER | IORING_SETUP_NO_SQARRAY;
	p.flags = flags;
	p.cq_entries = 64;
	int setup = io_uring_queue_init_params(32, &ring, &p);
	printf("{\"setup\":%d,\"uid\":%lu,\"flags\":%u,\"sq\":%u,\"cq\":%u,\"features\":%u,\"header_major\":%d,\"header_minor\":%d,\"library_major\":%d,\"library_minor\":%d", setup, (unsigned long)getuid(), p.flags, p.sq_entries, p.cq_entries, p.features, IO_URING_VERSION_MAJOR, IO_URING_VERSION_MINOR, io_uring_major_version(), io_uring_minor_version());
	if (setup < 0) {
		printf(",\"status\":\"BLOCKED\"}\n");
		return 77;
	}
	require(p.flags == flags && p.sq_entries == 32 && p.cq_entries == 64 && (p.features & IORING_FEAT_NODROP) && sizeof(struct io_uring_sqe) == 64 && sizeof(struct io_uring_cqe) == 16);
	require(io_uring_major_version() == 2 && io_uring_minor_version() == 15);
	struct io_uring_probe *probe = io_uring_get_probe_ring(&ring);
	require(probe != NULL);
	const int timers = io_uring_opcode_supported(probe, IORING_OP_TIMEOUT);
	const int cancel = io_uring_opcode_supported(probe, IORING_OP_ASYNC_CANCEL);
	io_uring_free_probe(probe);
	printf(",\"timeout_supported\":%d,\"cancel_supported\":%d,\"events\":[", timers, cancel);
	require(timers && cancel);
	uint64_t start = monotonic_ns();
	timeout(&ring, 20000000, 1);
	struct io_uring_cqe expiry = observe(&ring);
	uint64_t elapsed = monotonic_ns() - start;
	printf("{\"role\":\"target\",\"id\":%" PRIu64 ",\"res\":%d,\"elapsed_ns\":%" PRIu64 "}", (uint64_t)expiry.user_data, expiry.res, elapsed);
	require(expiry.user_data == 1 && expiry.res == -ETIME && elapsed >= 20000000);
	timeout(&ring, 2000000000, 2);
	struct io_uring_sqe *sqe = io_uring_get_sqe(&ring);
	require(sqe != NULL);
	io_uring_prep_cancel64(sqe, 2, 0);
	io_uring_sqe_set_data64(sqe, 3);
	require(io_uring_submit(&ring) == 1);
	unsigned target_seen = 0, cancel_seen = 0;
	for (unsigned n = 0; n < 2; n++) {
		struct io_uring_cqe completion = observe(&ring);
		printf(",{\"role\":\"%s\",\"id\":%" PRIu64 ",\"res\":%d}", completion.user_data == 2 ? "target" : "cancel", (uint64_t)completion.user_data, completion.res);
		if (completion.user_data == 2) {
			require(!target_seen && completion.res == -ECANCELED);
			target_seen = 1;
		} else {
			require(completion.user_data == 3 && !cancel_seen && completion.res == 0);
			cancel_seen = 1;
		}
	}
	require(target_seen && cancel_seen && io_uring_cq_ready(&ring) == 0 && io_uring_sq_ready(&ring) == 0);
	io_uring_queue_exit(&ring);
	printf("],\"observed_target_and_cancel\":true,\"status\":\"PASS\"}\n");
	return 0;
}
