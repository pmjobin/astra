/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <liburing.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* Early vertical kernel witness. This is a probe, not an Astra app or a
 * replacement for the scheduler/owner qualification. Run in task scratch. */
int main(void) {
	alarm(10);
	struct io_uring ring;
	struct io_uring_params p = {.flags = IORING_SETUP_CQSIZE |
	                                     IORING_SETUP_SINGLE_ISSUER | IORING_SETUP_NO_SQARRAY,
	                            .cq_entries = 64};
	assert(io_uring_queue_init_params(32, &ring, &p) == 0);
	int fd = open("payload-probe.bin", O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
	assert(fd >= 0);
	unsigned char written[4097], readback[4098];
	for (unsigned i = 0; i < sizeof(written); i++)
		written[i] = (unsigned char)(i * 37);
	struct io_uring_sqe *sqe = io_uring_get_sqe(&ring);
	assert(sqe);
	io_uring_prep_write(sqe, fd, written, sizeof(written), 0);
	io_uring_sqe_set_data64(sqe, 1);
	assert(io_uring_submit(&ring) == 1);
	struct io_uring_cqe *cqe;
	assert(io_uring_wait_cqe(&ring, &cqe) == 0);
	assert(cqe->user_data == 1 && cqe->res == (int)sizeof(written) && !cqe->flags);
	printf("write target=%" PRIu64 " result=%d\n", (uint64_t)cqe->user_data, cqe->res);
	io_uring_cqe_seen(&ring, cqe);
	sqe = io_uring_get_sqe(&ring);
	assert(sqe);
	memset(readback, 0xa5, sizeof(readback));
	io_uring_prep_read(sqe, fd, readback, sizeof(readback), 0);
	io_uring_sqe_set_data64(sqe, 2);
	assert(io_uring_submit(&ring) == 1);
	sqe = io_uring_get_sqe(&ring);
	assert(sqe);
	io_uring_prep_cancel64(sqe, 2, 0);
	io_uring_sqe_set_data64(sqe, 3);
	assert(io_uring_submit(&ring) == 1);
	unsigned target_seen = 0, cancel_seen = 0;
	for (unsigned i = 0; i < 2; i++) {
		assert(io_uring_wait_cqe(&ring, &cqe) == 0);
		printf("%s id=%" PRIu64 " result=%d\n", cqe->user_data == 2 ? "read target" : "cancel command",
		       (uint64_t)cqe->user_data, cqe->res);
		assert(!cqe->flags);
		if (cqe->user_data == 2) {
			assert(!target_seen++);
			assert(cqe->res == (int)sizeof(written) || cqe->res == -ECANCELED);
			if (cqe->res >= 0) assert(!memcmp(written, readback, sizeof(written)));
		} else {
			assert(cqe->user_data == 3 && !cancel_seen++);
			assert(cqe->res == 0 || cqe->res == -ENOENT || cqe->res == -EALREADY);
		}
		io_uring_cqe_seen(&ring, cqe);
	}
	assert(target_seen && cancel_seen && !io_uring_cq_ready(&ring) && !io_uring_sq_ready(&ring));
	assert(close(fd) == 0);
	io_uring_queue_exit(&ring);
	puts("real payload probe PASS; buffer/fd retained until both observed CQEs");
	return 0;
}
