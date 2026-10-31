// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Host capability probe only: this does not qualify generated Astra programs.
#define _GNU_SOURCE
#include <glib-object.h>
#include <liburing.h>
#include <stdio.h>
#include <string.h>

static gint completed;
static gpointer work(gpointer unused) {
	(void)unused;
	g_atomic_int_inc(&completed);
	return NULL;
}
int main(int argc, char **argv) {
	GObject *object = g_object_new(G_TYPE_OBJECT, NULL);
	GWeakRef weak;
	g_weak_ref_init(&weak, object);
	g_object_unref(object);
	g_assert_null(g_weak_ref_get(&weak));
	g_weak_ref_clear(&weak);
	GThread *thread = g_thread_new("m18-probe", work, NULL);
	g_thread_join(thread);
	g_assert_cmpint(g_atomic_int_get(&completed), ==, 1);
	if (argc == 2 && strcmp(argv[1], "--uring") == 0) {
		struct io_uring ring;
		int result = io_uring_queue_init(2, &ring, 0);
		if (result < 0) {
			fprintf(stderr, "io_uring_queue_init: %s (%d)\n", strerror(-result), result);
			return 77;
		}
		struct io_uring_sqe *sqe = io_uring_get_sqe(&ring);
		io_uring_prep_nop(sqe);
		g_assert_cmpint(io_uring_submit(&ring), ==, 1);
		struct io_uring_cqe *cqe;
		g_assert_cmpint(io_uring_wait_cqe(&ring, &cqe), ==, 0);
		g_assert_cmpint(cqe->res, ==, 0);
		io_uring_cqe_seen(&ring, cqe);
		io_uring_queue_exit(&ring);
	}
	puts("host GObject/thread/provider probe completed");
	return 0;
}
