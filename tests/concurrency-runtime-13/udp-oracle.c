// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
static pthread_t peer;
static int descriptor;
int32_t net_oracle_lifetimes(int32_t expected);

struct client {
	struct sockaddr_in address;
	int state;
	int id;
};

static void *serve_udp(void *unused) {
	(void)unused;
	struct client clients[2] = {0};
	int admitted = 0, finished = 0;
	uint8_t bytes[65535];
	while (finished < 2) {
		struct pollfd event = {.fd = descriptor, .events = POLLIN};
		assert(poll(&event, 1, 10000) == 1);
		struct sockaddr_in address;
		socklen_t length = sizeof(address);
		ssize_t count = recvfrom(descriptor, bytes, sizeof(bytes), 0, (struct sockaddr *)&address, &length);
		if (count < 0) {
			assert(errno == EAGAIN || errno == EINTR);
			continue;
		}
		assert(length == sizeof(address) && address.sin_family == AF_INET && address.sin_addr.s_addr == htonl(INADDR_LOOPBACK));
		int slot = -1;
		for (int i = 0; i < admitted; ++i)
			if (clients[i].address.sin_port == address.sin_port) slot = i;
		if (slot < 0) {
			assert(admitted < 2);
			slot = admitted++;
			clients[slot].address = address;
		}
		struct client *client = &clients[slot];
		if (client->state == 0) {
			assert(count == 0);
			assert(sendto(descriptor, bytes, 0, 0, (struct sockaddr *)&address, length) == 0);
		} else if (client->state == 1) {
			assert(count == 65507);
			client->id = bytes[0];
			assert(client->id == 1 || client->id == 2);
			for (int i = 0; i < count; ++i) {
				int expected = i % 251;
				if (i == 0)
					expected = client->id;
				else if (i == 1)
					expected = 0;
				else if (i == 2)
					expected = 195;
				else if (i == 3)
					expected = 169;
				assert(bytes[i] == expected);
			}
			assert(sendto(descriptor, bytes, (size_t)count, 0, (struct sockaddr *)&address, length) == count);
		} else if (client->state == 2) {
			assert(count == 1 && bytes[0] == 7);
			memset(bytes, 42, 100);
			assert(sendto(descriptor, bytes, 100, 0, (struct sockaddr *)&address, length) == 100);
		} else {
			assert(client->state == 3 && count == 1 && bytes[0] == 8);
			struct timespec delay = {.tv_nsec = 20000000};
			assert(nanosleep(&delay, NULL) == 0);
			const uint8_t reply[] = {65, 0, 195, 169, 33};
			assert(sendto(descriptor, reply, sizeof(reply), 0, (struct sockaddr *)&address, length) == sizeof(reply));
			++finished;
		}
		++client->state;
	}
	assert(admitted == 2 && clients[0].id != clients[1].id);
	assert(close(descriptor) == 0);
	return NULL;
}

int32_t udp_oracle_start(void) {
	descriptor = socket(AF_INET, SOCK_DGRAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
	assert(descriptor >= 0);
	struct sockaddr_in address = {.sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
	assert(bind(descriptor, (struct sockaddr *)&address, sizeof(address)) == 0);
	socklen_t length = sizeof(address);
	assert(getsockname(descriptor, (struct sockaddr *)&address, &length) == 0);
	assert(pthread_create(&peer, NULL, serve_udp, NULL) == 0);
	return ntohs(address.sin_port);
}

int32_t udp_oracle_finish(void) {
	assert(pthread_join(peer, NULL) == 0);
	net_oracle_lifetimes(3);
	puts("UDP: two producers, exact endpoints, empty/max/delayed datagrams, checked truncation and limits, three exact closes");
	return 0;
}
