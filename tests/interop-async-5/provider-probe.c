/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include <errno.h>
#include <liburing.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(void) {
	alarm(10);
	struct io_uring ring;
	struct io_uring_params p = {0};
	p.flags = IORING_SETUP_CQSIZE | IORING_SETUP_SINGLE_ISSUER | IORING_SETUP_NO_SQARRAY;
	p.cq_entries = 64;
	int rc = io_uring_queue_init_params(32, &ring, &p);
	printf("{\"setup\":%d,\"error\":\"%s\",\"uid\":%lu,\"flags\":%u,\"sq\":%u,\"cq\":%u,\"features\":%u,"
	       "\"header_major\":%d,\"header_minor\":%d,\"library_major\":%d,\"library_minor\":%d",
	       rc, rc < 0 ? strerror(-rc) : "none", (unsigned long)getuid(), p.flags,
	       p.sq_entries, p.cq_entries, p.features, IO_URING_VERSION_MAJOR, IO_URING_VERSION_MINOR,
	       io_uring_major_version(), io_uring_minor_version());
	if (rc < 0) {
		puts(",\"status\":\"ENVIRONMENT_BLOCKED\"}");
		return 77;
	}
	struct io_uring_probe *probe = io_uring_get_probe_ring(&ring);
	if (!probe) {
		puts(",\"status\":\"PROBE_FAILED\"}");
		io_uring_queue_exit(&ring);
		return 77;
	}
	int read_ok = io_uring_opcode_supported(probe, IORING_OP_READ);
	int write_ok = io_uring_opcode_supported(probe, IORING_OP_WRITE);
	int cancel_ok = io_uring_opcode_supported(probe, IORING_OP_ASYNC_CANCEL);
	printf(",\"read\":%d,\"write\":%d,\"cancel\":%d,\"status\":\"%s\"}\n",
	       read_ok, write_ok, cancel_ok, read_ok && write_ok && cancel_ok ? "AVAILABLE" : "ENVIRONMENT_BLOCKED");
	io_uring_free_probe(probe);
	io_uring_queue_exit(&ring);
	return read_ok && write_ok && cancel_ok ? 0 : 77;
}
