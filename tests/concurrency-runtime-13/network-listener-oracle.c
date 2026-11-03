// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

extern int32_t net_oracle_lifetimes(int32_t expected);
static pthread_t peers[8];
static pthread_barrier_t connected;
static int port, clients, seed, guard;

static void ready(int fd, short events) {
	struct pollfd pollfd = {.fd = fd, .events = events};
	int result;
	do {
		result = poll(&pollfd, 1, 10000);
	} while (result < 0 && errno == EINTR);
	assert(result == 1 && !(pollfd.revents & POLLNVAL));
}

static void *exchange(void *opaque) {
	int id = (int)(uintptr_t)opaque;
	int socket_fd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
	assert(socket_fd >= 0);
	struct sockaddr_in address = {.sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK), .sin_port = htons((uint16_t)port)};
	int status = connect(socket_fd, (struct sockaddr *)&address, sizeof(address));
	if (status < 0) {
		assert(errno == EINPROGRESS);
		ready(socket_fd, POLLOUT);
		int error = -1;
		socklen_t length = sizeof(error);
		assert(getsockopt(socket_fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 && error == 0);
	}
	status = pthread_barrier_wait(&connected);
	assert(status == 0 || status == PTHREAD_BARRIER_SERIAL_THREAD);
	uint8_t wire[4096], reply[4096];
	for (int frame = 0; frame < 4; ++frame) {
		uint8_t *base = wire + frame * 1024;
		base[0] = 0;
		base[1] = 0;
		base[2] = 3;
		base[3] = 252;
		for (int i = 0; i < 1020; ++i)
			base[4 + i] = (uint8_t)((id * 17 + seed + frame * 31 + i) % 251);
		base[4] = (uint8_t)id;
		base[5] = 0;
		base[6] = 195;
		base[7] = 169;
	}
	size_t sent = 0, used = 0;
	while (sent < sizeof(wire)) {
		ready(socket_fd, POLLOUT);
		size_t count = sizeof(wire) - sent;
		if (count > 37) count = 37;
		ssize_t progress = send(socket_fd, wire + sent, count, MSG_NOSIGNAL);
		if (progress < 0) {
			assert(errno == EAGAIN || errno == EINTR);
			continue;
		}
		assert(progress > 0);
		sent += (size_t)progress;
	}
	assert(shutdown(socket_fd, SHUT_WR) == 0);
	while (used < sizeof(reply)) {
		ready(socket_fd, POLLIN);
		size_t count = sizeof(reply) - used;
		if (count > 17) count = 17;
		ssize_t progress = recv(socket_fd, reply + used, count, 0);
		if (progress < 0) {
			assert(errno == EAGAIN || errno == EINTR);
			continue;
		}
		assert(progress > 0);
		used += (size_t)progress;
	}
	assert(memcmp(wire, reply, sizeof(wire)) == 0);
	uint8_t extra;
	ready(socket_fd, POLLIN);
	assert(recv(socket_fd, &extra, 1, 0) == 0);
	assert(close(socket_fd) == 0);
	return NULL;
}

int32_t listener_oracle_start(int32_t endpoint, int32_t count, int32_t schedule) {
	assert(endpoint > 0 && endpoint <= 65535 && count >= 2 && count <= 8);
	port = endpoint;
	clients = count;
	seed = schedule;
	assert(pthread_barrier_init(&connected, NULL, (unsigned)clients) == 0);
	for (int i = 0; i < clients; ++i)
		assert(pthread_create(&peers[i], NULL, exchange, (void *)(uintptr_t)(i + 1)) == 0);
	return 0;
}

int32_t listener_oracle_guard(void) {
	guard = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
	assert(guard >= 0);
	struct sockaddr_in address = {.sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
	assert(bind(guard, (struct sockaddr *)&address, sizeof(address)) == 0);
	socklen_t length = sizeof(address);
	assert(getsockname(guard, (struct sockaddr *)&address, &length) == 0);
	return ntohs(address.sin_port);
}

int32_t listener_oracle_guard_close(void) {
	assert(close(guard) == 0);
	return 0;
}

int32_t listener_oracle_finish(int32_t expected) {
	assert(expected == clients);
	for (int i = 0; i < clients; ++i)
		assert(pthread_join(peers[i], NULL) == 0);
	assert(pthread_barrier_destroy(&connected) == 0);
	net_oracle_lifetimes(2 * clients + 4);
	printf("Astra TCP listener: %d concurrent peers, exact binary frames, refused connect, busy bind, bounded buffers, all sockets closed\n", clients);
	return 0;
}
