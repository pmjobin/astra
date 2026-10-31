// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define WIRE 262160
static pthread_t peer;
static int listener;
static _Atomic int opens, closes, again, partial, eof;
static pthread_mutex_t fd_lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned char live_fd[4096];
int32_t net_oracle_lifetimes(int32_t expected) {
	assert(atomic_load(&opens) == expected && atomic_load(&closes) == expected);
	return 0;
}
int __real_socket(int, int, int);
int __real_accept4(int, struct sockaddr *, socklen_t *, int);
int __real_close(int);
ssize_t __real_send(int, const void *, size_t, int);
ssize_t __real_recv(int, void *, size_t, int);
static int admit(int fd) {
	if (fd >= 0) {
		assert(fd < 4096);
		assert(pthread_mutex_lock(&fd_lock) == 0);
		assert(live_fd[fd] == 0);
		live_fd[fd] = 1;
		assert(pthread_mutex_unlock(&fd_lock) == 0);
		atomic_fetch_add(&opens, 1);
	}
	return fd;
}
int __wrap_socket(int a, int b, int c) {
	return admit(__real_socket(a, b, c));
}
int __wrap_accept4(int a, struct sockaddr *b, socklen_t *c, int d) {
	return admit(__real_accept4(a, b, c, d));
}
int __wrap_close(int fd) {
	assert(pthread_mutex_lock(&fd_lock) == 0);
	int tracked = fd >= 0 && fd < 4096 && live_fd[fd];
	if (tracked) {
		live_fd[fd] = 0;
		atomic_fetch_add(&closes, 1);
	}
	assert(pthread_mutex_unlock(&fd_lock) == 0);
	return __real_close(fd);
}
ssize_t __wrap_send(int fd, const void *data, size_t count, int flags) {
	ssize_t result = __real_send(fd, data, count, flags);
	if (result < 0 && errno == EAGAIN) atomic_fetch_add(&again, 1);
	if (result > 0 && (size_t)result < count) atomic_fetch_add(&partial, 1);
	return result;
}
ssize_t __wrap_recv(int fd, void *data, size_t count, int flags) {
	ssize_t result = __real_recv(fd, data, count, flags);
	if (result == 0 && count != 0) atomic_fetch_add(&eof, 1);
	return result;
}
static void ready(int fd, short events) {
	struct pollfd event = {.fd = fd, .events = events};
	int result;
	do {
		result = poll(&event, 1, 10000);
	} while (result < 0 && errno == EINTR);
	assert(result == 1 && !(event.revents & POLLNVAL));
}
static void *serve(void *unused) {
	(void)unused;
	int clients[2];
	for (int i = 0; i < 2; ++i) {
		ready(listener, POLLIN);
		clients[i] = accept4(listener, NULL, NULL, SOCK_NONBLOCK | SOCK_CLOEXEC);
		assert(clients[i] >= 0);
	}
	/* Force real bounded send-buffer backpressure after both connect. */
	struct timespec pause = {.tv_nsec = 50000000};
	assert(nanosleep(&pause, NULL) == 0);
	uint8_t *wire[2] = {malloc(WIRE), malloc(WIRE)};
	assert(wire[0] && wire[1]);
	size_t used[2] = {0, 0};
	int ended[2] = {0, 0};
	while (!ended[0] || !ended[1]) {
		struct pollfd events[2];
		for (int i = 0; i < 2; ++i)
			events[i] = (struct pollfd){.fd = ended[i] ? -1 : clients[i], .events = POLLIN};
		assert(poll(events, 2, 10000) > 0);
		for (int i = 0; i < 2; ++i) {
			if (!events[i].revents) continue;
			uint8_t extra;
			ssize_t count = recv(clients[i], used[i] < WIRE ? wire[i] + used[i] : &extra,
			                     used[i] < WIRE ? WIRE - used[i] : 1, 0);
			if (count < 0) {
				assert(errno == EAGAIN || errno == EINTR);
				continue;
			}
			if (count == 0) {
				assert(used[i] == WIRE);
				ended[i] = 1;
			} else {
				assert(used[i] < WIRE);
				used[i] += (size_t)count;
			}
		}
	}
	unsigned identities = 0;
	for (int c = 0; c < 2; ++c) {
		int id = wire[c][4];
		assert(id == 1 || id == 2);
		assert(!(identities & (1u << id)));
		identities |= 1u << id;
		for (int frame = 0; frame < 4; ++frame) {
			const uint8_t *base = wire[c] + frame * 65540;
			assert(base[0] == 0 && base[1] == 1 && base[2] == 0 && base[3] == 0);
			for (int i = 0; i < 65536; ++i) {
				int index = frame * 65536 + i;
				int expected = index % 251;
				if (index == 0)
					expected = id;
				else if (index == 1)
					expected = 0;
				else if (index == 2)
					expected = 195;
				else if (index == 3)
					expected = 169;
				assert(base[4 + i] == expected);
			}
		}
		size_t sent = 0;
		while (sent < WIRE) {
			ready(clients[c], POLLOUT);
			size_t count = WIRE - sent;
			if (count > 4093) count = 4093;
			ssize_t result = send(clients[c], wire[c] + sent, count, MSG_NOSIGNAL);
			if (result < 0) {
				assert(errno == EAGAIN || errno == EINTR);
				continue;
			}
			assert(result > 0);
			sent += (size_t)result;
		}
		assert(shutdown(clients[c], SHUT_WR) == 0);
		assert(close(clients[c]) == 0);
		free(wire[c]);
	}
	assert(close(listener) == 0);
	return NULL;
}
int32_t tcp_oracle_start(void) {
	listener = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
	assert(listener >= 0);
	struct sockaddr_in address = {.sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
	assert(bind(listener, (struct sockaddr *)&address, sizeof(address)) == 0);
	assert(listen(listener, 2) == 0);
	socklen_t size = sizeof(address);
	assert(getsockname(listener, (struct sockaddr *)&address, &size) == 0);
	assert(pthread_create(&peer, NULL, serve, NULL) == 0);
	return ntohs(address.sin_port);
}
int32_t tcp_oracle_finish(void) {
	assert(pthread_join(peer, NULL) == 0);
	assert(atomic_load(&opens) == 5 && atomic_load(&closes) == 5);
	assert(atomic_load(&again) > 0 && atomic_load(&partial) > 0 && atomic_load(&eof) >= 4);
	puts("TCP: two concurrent sessions, eight exact binary frames, backpressure, half-close, five exact closes");
	return 0;
}
