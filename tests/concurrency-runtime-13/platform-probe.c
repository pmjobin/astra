// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static _Atomic uint64_t counter;
static pthread_barrier_t barrier;

static void *worker(void *argument) {
	(void)argument;
	int status = pthread_barrier_wait(&barrier);
	assert(status == 0 || status == PTHREAD_BARRIER_SERIAL_THREAD);
	for (int i = 0; i < 10000; ++i)
		atomic_fetch_add_explicit(&counter, 1, memory_order_acq_rel);
	return NULL;
}

static int endpoint(int kind, struct sockaddr_in *address) {
	int fd = socket(AF_INET, kind | SOCK_CLOEXEC, 0);
	assert(fd >= 0);
	*address = (struct sockaddr_in){.sin_family = AF_INET,
	                                .sin_addr.s_addr = htonl(INADDR_LOOPBACK),
	                                .sin_port = 0};
	assert(bind(fd, (struct sockaddr *)address, sizeof(*address)) == 0);
	socklen_t size = sizeof(*address);
	assert(getsockname(fd, (struct sockaddr *)address, &size) == 0);
	assert(size == sizeof(*address) && address->sin_port != 0);
	return fd;
}

int main(void) {
	pthread_t threads[4];
	assert(pthread_barrier_init(&barrier, NULL, 4) == 0);
	for (int i = 0; i < 4; ++i)
		assert(pthread_create(&threads[i], NULL, worker, NULL) == 0);
	for (int i = 0; i < 4; ++i)
		assert(pthread_join(threads[i], NULL) == 0);
	assert(pthread_barrier_destroy(&barrier) == 0);
	assert(atomic_load_explicit(&counter, memory_order_acquire) == 40000);
	assert(atomic_is_lock_free(&counter));

	struct sockaddr_in address;
	const unsigned char payload[] = {0, 255, 0xe2, 0x98, 0x83, 42};
	unsigned char received[sizeof(payload)];
	int listener = endpoint(SOCK_STREAM, &address);
	assert(listen(listener, 2) == 0);
	int client = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
	assert(client >= 0);
	assert(connect(client, (struct sockaddr *)&address, sizeof(address)) == 0);
	int peer = accept(listener, NULL, NULL);
	assert(peer >= 0);
	assert(send(client, payload, sizeof(payload), MSG_NOSIGNAL) == sizeof(payload));
	assert(recv(peer, received, sizeof(received), MSG_WAITALL) == sizeof(received));
	assert(memcmp(payload, received, sizeof(payload)) == 0);
	assert(shutdown(client, SHUT_WR) == 0);
	assert(recv(peer, received, sizeof(received), 0) == 0);
	assert(close(peer) == 0 && close(client) == 0 && close(listener) == 0);

	int receiver = endpoint(SOCK_DGRAM, &address);
	int sender = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	assert(sender >= 0);
	assert(sendto(sender, payload, sizeof(payload), 0,
	              (struct sockaddr *)&address, sizeof(address)) == sizeof(payload));
	assert(recv(receiver, received, sizeof(received), 0) == sizeof(received));
	assert(memcmp(payload, received, sizeof(payload)) == 0);
	assert(fcntl(receiver, F_SETFL, O_NONBLOCK) == 0);
	assert(recv(receiver, received, sizeof(received), 0) == -1);
	assert(errno == EAGAIN || errno == EWOULDBLOCK);
	assert(close(sender) == 0 && close(receiver) == 0);
	puts("platform: 4 pthreads, 40000 atomic RMWs, kernel TCP/UDP binary bytes, EOF, EAGAIN: OK");
	return 0;
}
