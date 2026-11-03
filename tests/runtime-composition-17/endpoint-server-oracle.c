/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _POSIX_C_SOURCE 200809L
#include "../../lib/runtime/platform/network-posix.h"
#include "../../lib/runtime/runtime/context-17.h"
#include <arpa/inet.h>
#include <assert.h>
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static int baseline_fds, scenario, observed, accepted, accepted_family;
static unsigned allocations, releases;
static int first_observation, second_observation, third_observation;
static void *payloads[3];
static uint64_t tags[3];

static int inventory(void) {
	DIR *directory = opendir("/proc/self/fd");
	assert(directory);
	int count = 0;
	struct dirent *entry;
	while ((entry = readdir(directory))) {
		if (entry->d_name[0] != '.') {
			++count;
		}
	}
	assert(closedir(directory) == 0);
	return count;
}

void endpoint_server_prepare(void) {
	const char *setting = getenv("M17_SERVER_MODE");
	assert(setting);
	scenario = atoi(setting);
	assert(scenario >= 0 && scenario <= 4);
	baseline_fds = inventory();
}

int endpoint_server_mode(void) {
	return scenario;
}

void endpoint_server_ready(int tcp, int udp) {
	assert(tcp >= 1024 && tcp <= 65535 && udp >= 1024 && udp <= 65535);
	const char *path = getenv("M17_SERVER_READY_PATH");
	assert(path);
	char temporary[4096];
	assert(snprintf(temporary, sizeof(temporary), "%s.tmp", path) < (int)sizeof(temporary));
	FILE *file = fopen(temporary, "w");
	assert(file);
	assert(fprintf(file, "{\"tcp\":%d,\"udp\":%d}\n", tcp, udp) > 0);
	assert(fclose(file) == 0 && rename(temporary, path) == 0);
}

extern int __real_astra_net_accept_from(int, AstraNetEndpoint *);

int __wrap_astra_net_accept_from(int descriptor, AstraNetEndpoint *endpoint) {
	int result = __real_astra_net_accept_from(descriptor, endpoint);
	if (result < 0) {
		return result;
	}
	assert(accepted++ == 0);
	accepted_family = endpoint->family;
	assert((fcntl(result, F_GETFD) & FD_CLOEXEC) && (fcntl(result, F_GETFL) & O_NONBLOCK));
	struct sockaddr_storage peer;
	socklen_t size = sizeof(peer);
	assert(getpeername(result, (struct sockaddr *)&peer, &size) == 0);
	if (peer.ss_family == AF_INET) {
		const struct sockaddr_in *address = (const struct sockaddr_in *)&peer;
		unsigned char canonical[16] = {0};
		memcpy(canonical, &address->sin_addr, 4);
		assert(endpoint->family == 4 && endpoint->port == ntohs(address->sin_port));
		assert(memcmp(endpoint->address, canonical, 16) == 0 && endpoint->scope == 0);
	} else {
		const struct sockaddr_in6 *address = (const struct sockaddr_in6 *)&peer;
		assert(peer.ss_family == AF_INET6 && endpoint->family == 6 && endpoint->port == ntohs(address->sin6_port));
		assert(memcmp(endpoint->address, &address->sin6_addr, 16) == 0 && endpoint->scope == address->sin6_scope_id);
	}
	return result;
}

extern void *__real_astra_context17_allocate_mode(AstraContext17 *, uint64_t,
                                                  uint64_t, uint32_t, uint64_t, uint32_t);
extern int __real_astra_context17_release_origin_checked(void *, uint64_t);

void *__wrap_astra_context17_allocate_mode(AstraContext17 *context, uint64_t count,
                                           uint64_t size, uint32_t alignment, uint64_t tag, uint32_t mode) {
	assert(allocations < 3 && size == 1 && mode == 2 && tag != 0);
	assert(count == 4 || count == 8193 || count == 65507 || count == 65527);
	void *pointer = __real_astra_context17_allocate_mode(context, count, size, alignment, tag, mode);
	assert(pointer && astra_context17_origin(pointer, tag) == context);
	payloads[allocations] = pointer;
	tags[allocations++] = tag;
	return pointer;
}

int __wrap_astra_context17_release_origin_checked(void *pointer, uint64_t tag) {
	unsigned slot = 0;
	while (slot < allocations && payloads[slot] != pointer) {
		++slot;
	}
	assert(slot < allocations && tags[slot] == tag);
	payloads[slot] = NULL;
	++releases;
	return __real_astra_context17_release_origin_checked(pointer, tag);
}

void endpoint_server_observed(int first, int second, int third) {
	assert(observed++ == 0 && accepted == 1);
	first_observation = first;
	second_observation = second;
	third_observation = third;
	if (scenario == 0) {
		assert(first == 8193 && second == 4 && third == (accepted_family == 4 ? 65507 : 65527));
	}
	if (scenario == 1) {
		assert(first == 2 && second == 0 && third == 0);
	}
	if (scenario == 2) {
		assert(first >= 120 && first < 5000 && second == -110 && third == 0);
	}
	if (scenario == 3) {
		assert(first == 2 && second == -104 && third == -32);
	}
	if (scenario == 4) {
		if (first != 1048577 || second <= 0 || third <= 0) {
			fprintf(stderr, "backpressure observed %d %d %d\n", first, second, third);
		}
		assert(first == 1048577 && second > 0 && third > 0);
	}
}

int endpoint_server_finish(int result) {
	if (result != 0) {
		fprintf(stderr, "server source result %d\n", result);
		return result;
	}
	assert(observed == 1 && accepted == 1 && allocations == releases);
	assert(allocations == (scenario == 0 ? 3U : 1U) && inventory() == baseline_fds);
	printf("observed=%d,%d,%d; allocations=%u; releases=%u; fds=%d\n", first_observation, second_observation, third_observation, allocations, releases, baseline_fds);
	puts("endpoint server: typed peer, bounded context bytes, progress/error contract and exact FD retirement");
	return 0;
}
