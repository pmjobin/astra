/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _POSIX_C_SOURCE 200809L
#include "files-posix.h"
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <limits.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#if !defined(__linux__) || !defined(__x86_64__) || defined(__ILP32__)
#error "files-posix is qualified only for GNU Linux x86-64 LP64"
#endif
_Static_assert(CHAR_BIT == 8 && sizeof(int) == 4 && sizeof(int32_t) == 4, "I32/octet ABI");
_Static_assert(sizeof(void *) == 8 && sizeof(size_t) == 8 && sizeof(ssize_t) == 8 && SIZE_MAX > INT32_MAX, "LP64 pointer/transfer contract");

/* All paths are authentic counted UTF-8 views. Copy only for the POSIX name;
 * never retain the view or treat payload bytes as a terminated string. */
int32_t astra_file_open(const unsigned char *path, int32_t length, int32_t mode) {
	if (length < 0 || (length && !path) || (mode != 0 && mode != 1)) {
		return -EINVAL;
	}
	for (int32_t i = 0; i < length; i++) {
		if (path[i] == 0) {
			return -EINVAL;
		}
	}
	char *name = malloc((size_t)length + 1);
	if (!name) {
		abort();
	} /* Existing hosted fatal OOM policy. */
	for (int32_t i = 0; i < length; i++) {
		name[i] = (char)path[i];
	}
	name[length] = 0;
	int fd;
	do {
		fd = open(name, mode == 0 ? O_RDONLY | O_CLOEXEC : O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0666);
	} while (fd < 0 && errno == EINTR);
	int error = errno;
	free(name);
	return fd < 0 ? -error : fd;
}

/* One bounded transfer per call. Astra owns all full-file storage and loops. */
int32_t astra_file_read_byte(int32_t fd) {
	unsigned char byte;
	ssize_t count;
	do {
		count = read(fd, &byte, 1);
	} while (count < 0 && errno == EINTR);
	if (count == 0) {
		return -1;
	}
	return count < 0 ? -1 - errno : byte;
}

int32_t astra_file_write_byte(int32_t fd, int32_t byte) {
	if (byte < 0 || byte > 255) {
		return -EINVAL;
	}
	unsigned char value = (unsigned char)byte;
	ssize_t count;
	do {
		count = write(fd, &value, 1);
	} while (count < 0 && errno == EINTR);
	return count == 1 ? 0 : count == 0 ? -EIO
	                                   : -errno;
}

static int valid_range(const unsigned char *data, int32_t length, int32_t offset, int32_t count) {
	return length >= 0 && offset >= 0 && count >= 0 && offset <= length && count <= length - offset && (!length || data);
}

int32_t astra_file_read_buffer(int32_t fd, unsigned char *data, int32_t length, int32_t offset, int32_t count) {
	if (!valid_range(data, length, offset, count)) {
		return -EINVAL;
	}
	if (!count) {
		return 0;
	}
	size_t requested = (size_t)(count > 65536 ? 65536 : count);
	ssize_t progress;
	do {
		progress = read(fd, data + offset, requested);
	} while (progress < 0 && errno == EINTR);
	return progress < 0 ? -errno : (int32_t)progress;
}

int32_t astra_file_write_buffer(int32_t fd, const unsigned char *data, int32_t length, int32_t offset, int32_t count) {
	if (!valid_range(data, length, offset, count)) {
		return -EINVAL;
	}
	if (!count) {
		return 0;
	}
	size_t requested = (size_t)(count > 65536 ? 65536 : count);
	ssize_t progress;
	do {
		progress = write(fd, data + offset, requested);
	} while (progress < 0 && errno == EINTR);
	return progress < 0 ? -errno : progress == 0 ? -EIO
	                                             : (int32_t)progress;
}

int32_t astra_file_write_text(int32_t fd, const unsigned char *data, int32_t length, int32_t offset, int32_t count) {
	return astra_file_write_buffer(fd, data, length, offset, count);
}

int32_t astra_file_flush(int32_t fd) {
	int result;
	do {
		result = fsync(fd);
	} while (result < 0 && errno == EINTR);
	return result < 0 ? -errno : 0;
}

int32_t astra_file_close(int32_t fd) {
	/* Linux releases the fd even on EINTR; retry could close a reused fd. */
	return close(fd) < 0 ? -errno : 0;
}
