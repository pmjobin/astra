/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _GNU_SOURCE
#include "../../lib/runtime/runtime/context-17.h"
#include <arpa/inet.h>
#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <unistd.h>

static int baseline, reservation = -1, descriptors[128], count, restored, reservations;
static unsigned contexts;
static struct rlimit original;

static int inventory(void) {
	DIR *directory = opendir("/proc/self/fd");
	assert(directory);
	int result = 0;
	struct dirent *entry;
	while ((entry = readdir(directory))) {
		if (entry->d_name[0] != '.') {
			++result;
		}
	}
	assert(closedir(directory) == 0);
	return result;
}

void endpoint_errors_prepare(void) {
	baseline = inventory();
}

int endpoint_refusal_port(int family) {
	assert(reservation == -1 && (family == 4 || family == 6));
	reservation = socket(family == 4 ? AF_INET : AF_INET6, SOCK_STREAM | SOCK_CLOEXEC, 0);
	assert(reservation >= 0);
	++reservations;
	if (family == 4) {
		struct sockaddr_in address = {.sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
		assert(bind(reservation, (struct sockaddr *)&address, sizeof(address)) == 0);
		socklen_t length = sizeof(address);
		assert(getsockname(reservation, (struct sockaddr *)&address, &length) == 0);
		return ntohs(address.sin_port);
	}
	struct sockaddr_in6 address = {.sin6_family = AF_INET6, .sin6_addr = IN6ADDR_LOOPBACK_INIT};
	assert(bind(reservation, (struct sockaddr *)&address, sizeof(address)) == 0);
	socklen_t length = sizeof(address);
	assert(getsockname(reservation, (struct sockaddr *)&address, &length) == 0);
	return ntohs(address.sin6_port);
}

void endpoint_refusal_close(void) {
	assert(reservation >= 0 && close(reservation) == 0);
	reservation = -1;
}

void endpoint_exhaust_descriptors(void) {
	assert(count == 0 && getrlimit(RLIMIT_NOFILE, &original) == 0);
	struct rlimit limit = original;
	if (limit.rlim_cur > 128) {
		limit.rlim_cur = 128;
	}
	assert(setrlimit(RLIMIT_NOFILE, &limit) == 0);
	while (count < 128) {
		int descriptor = open("/dev/null", O_RDONLY | O_CLOEXEC);
		if (descriptor < 0) {
			assert(errno == EMFILE);
			break;
		}
		descriptors[count++] = descriptor;
	}
	assert(count > 0 && count < 128);
}

void endpoint_restore_descriptors(void) {
	assert(restored++ == 0 && setrlimit(RLIMIT_NOFILE, &original) == 0);
	while (count > 0) {
		assert(close(descriptors[--count]) == 0);
	}
}

extern void __real_astra_context17_destroy(AstraContext17 *);

void __wrap_astra_context17_destroy(AstraContext17 *context) {
	AstraContext17Snapshot state;
	assert(context && astra_context17_snapshot(context, &state) == ASTRA_CONTEXT17_OK);
	assert(state.live == 0 && state.anchors == 1 && contexts++ == 0);
	__real_astra_context17_destroy(context);
}

int endpoint_errors_finish(int result) {
	if (result != 0) {
		fprintf(stderr, "endpoint errors source result %d\n", result);
		return result;
	}
	assert(reservation == -1 && reservations == 2 && contexts == 1 && count == 0 && restored == 1);
	struct rlimit current;
	assert(getrlimit(RLIMIT_NOFILE, &current) == 0);
	assert(current.rlim_cur == original.rlim_cur && current.rlim_max == original.rlim_max && inventory() == baseline);
	puts("endpoint errors: ranges, formats, refusal, oversize, actual EMFILE and recovery; FD/context conservation");
	return 0;
}
