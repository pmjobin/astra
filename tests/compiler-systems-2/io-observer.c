/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Test-only progress faults and syscall counts; application loops stay Astra. */
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int __real_open(const char *, int, ...);
ssize_t __real_read(int, void *, size_t);
ssize_t __real_write(int, const void *, size_t);
int __real_fsync(int);
int __real_close(int);
static bool active[1024];
static unsigned reads, writes, opens, flushes, closes, read_interrupt, write_interrupt;
static unsigned long long read_bytes, written_bytes;
static bool mode(const char *name) {
	const char *s = getenv("CS_IO_MODE");
	return s && !strcmp(s, name);
}
int __wrap_open(const char *path, int flags, ...) {
	mode_t permissions = 0;
	if (flags & O_CREAT) {
		va_list args;
		va_start(args, flags);
		permissions = va_arg(args, int);
		va_end(args);
	}
	int fd = __real_open(path, flags, permissions);
	opens++;
	if (fd >= 0) {
		assert(fd < 1024 && !active[fd]);
		active[fd] = true;
	}
	return fd;
}
ssize_t __wrap_read(int fd, void *bytes, size_t count) {
	assert(fd >= 0 && fd < 1024 && active[fd] && count > 0);
	reads++;
	if (mode("eintr") && !read_interrupt++) {
		errno = EINTR;
		return -1;
	}
	if (mode("read-error") && reads == 2) {
		errno = EIO;
		return -1;
	}
	if (mode("eagain")) {
		errno = EAGAIN;
		return -1;
	}
	if ((mode("short") || mode("read-error")) && count > 997) {
		count = 997;
	}
	ssize_t result = __real_read(fd, bytes, count);
	if (result > 0) {
		read_bytes += (unsigned long long)result;
	}
	return result;
}
ssize_t __wrap_write(int fd, const void *bytes, size_t count) {
	if (fd <= 2) {
		return __real_write(fd, bytes, count);
	}
	assert(fd < 1024 && active[fd] && count > 0);
	writes++;
	if (mode("eintr") && !write_interrupt++) {
		errno = EINTR;
		return -1;
	}
	if (mode("write-error") && writes == 2) {
		errno = EIO;
		return -1;
	}
	if (mode("zero")) {
		return 0;
	}
	if ((mode("short") || mode("write-error")) && count > 613) {
		count = 613;
	}
	ssize_t result = __real_write(fd, bytes, count);
	if (result > 0) {
		written_bytes += (unsigned long long)result;
	}
	return result;
}
int __wrap_fsync(int fd) {
	assert(fd >= 0 && fd < 1024 && active[fd]);
	flushes++;
	if (mode("flush")) {
		errno = EIO;
		return -1;
	}
	return __real_fsync(fd);
}
int __wrap_close(int fd) {
	assert(fd >= 0 && fd < 1024 && active[fd]);
	closes++;
	active[fd] = false;
	int result = __real_close(fd);
	if (mode("close")) {
		errno = EINTR;
		return -1;
	}
	return result;
}
__attribute__((destructor)) static void finish(void) {
	for (int fd = 0; fd < 1024; fd++) {
		assert(!active[fd]);
	}
	const char *path = getenv("CS_IO_REPORT");
	if (path) {
		FILE *file = fopen(path, "w");
		assert(file);
		fprintf(file, "{\"reads\":%u,\"writes\":%u,\"opens\":%u,\"closes\":%u,\"flushes\":%u,\"read_bytes\":%llu,\"written_bytes\":%llu}\n",
		        reads, writes, opens, closes, flushes, read_bytes, written_bytes);
		assert(fclose(file) == 0);
	}
}
