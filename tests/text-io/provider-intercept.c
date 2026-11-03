/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _POSIX_C_SOURCE 200809L
#include "../../lib/runtime/platform/text-posix.h"
#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
static int events[32], event_count, calls;
static size_t counts[32], emitted_count;
static unsigned char emitted[64];

ssize_t intercepted_write(int fd, const void *bytes, size_t count) {
	assert(fd == 1 || fd == 2);
	assert(count > 0 && calls < 32);
	counts[calls] = count;
	int event = calls < event_count ? events[calls] : 99;
	calls++;
	if (event < 0) {
		errno = event == -1 ? EINTR : event == -2 ? EAGAIN
		                          : event == -3   ? EWOULDBLOCK
		                                          : EIO;
		return -1;
	}
	size_t progress = (size_t)event < count ? (size_t)event : count;
	assert(emitted_count + progress <= sizeof emitted);
	memcpy(emitted + emitted_count, bytes, progress);
	emitted_count += progress;
	return (ssize_t)progress;
}

int main(int argc, char **argv) {
	assert(argc >= 5 && argc <= 36);
	static const unsigned char payload[] = {'a', 0, 'b', '%', 'n'};
	int stream = atoi(argv[1]), length = atoi(argv[2]), newline = atoi(argv[3]), null_data = atoi(argv[4]);
	for (int i = 5; i < argc; i++) {
		events[event_count++] = atoi(argv[i]);
	}
	int status = astra_host_text_write(stream, null_data ? NULL : payload, length, newline);
	printf("{\"status\":%d,\"calls\":%d,\"counts\":[", status, calls);
	for (int i = 0; i < calls; i++) {
		printf(i == 0 ? "%zu" : ",%zu", counts[i]);
	}
	printf("],\"hex\":\"");
	for (size_t i = 0; i < emitted_count; i++) {
		printf("%02x", emitted[i]);
	}
	puts("\"}");
	return 0;
}
