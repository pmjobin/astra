/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Test-only syscall faults and actual fd lifetime audit. No production logic. */
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
int __real_open(const char *, int, ...);
ssize_t __real_read(int, void *, size_t);
ssize_t __real_write(int, const void *, size_t);
int __real_fsync(int);
int __real_close(int);
static bool active[128];
static int reads, writes, injected_open, injected_read, injected_write, injected_flush, injected_close;
static bool selected(const char *name) {
	const char *value = getenv("ASTRA_IO_FAULT");
	return value && !strcmp(value, name);
}
int __wrap_open(const char *name, int flags, ...) {
	mode_t mode = 0;
	if (flags & O_CREAT) {
		va_list ap;
		va_start(ap, flags);
		mode = (mode_t)va_arg(ap, int);
		va_end(ap);
	}
	if (selected("eintr") && !injected_open++) {
		errno = EINTR;
		return -1;
	}
	int fd = __real_open(name, flags, mode);
	if (fd >= 0) {
		assert(fd < 128 && !active[fd]);
		active[fd] = true;
	}
	return fd;
}
ssize_t __wrap_read(int fd, void *data, size_t size) {
	assert(fd >= 0 && fd < 128 && active[fd] && size > 0 && size <= 65536);
	if (selected("eintr") && !injected_read++) {
		errno = EINTR;
		return -1;
	}
	if (selected("read") && reads++ == 1) {
		errno = EIO;
		return -1;
	}
	/* Keep the original one-byte partial-progress fault witness with bulk I/O. */
	if (selected("read")) {
		size = 1;
	}
	return __real_read(fd, data, size);
}
ssize_t __wrap_write(int fd, const void *data, size_t size) {
	if (fd <= 2) {
		return __real_write(fd, data, size);
	}
	assert(fd < 128 && active[fd] && size > 0 && size <= 65536);
	if (selected("eintr") && !injected_write++) {
		errno = EINTR;
		return -1;
	}
	if (selected("write") && writes++ == 1) {
		errno = EIO;
		return -1;
	}
	if (selected("write")) {
		size = 1;
	}
	if (selected("zero") && !injected_write++) {
		return 0;
	}
	return __real_write(fd, data, size);
}
int __wrap_fsync(int fd) {
	assert(fd >= 0 && fd < 128 && active[fd]);
	if (selected("eintr") && !injected_flush++) {
		errno = EINTR;
		return -1;
	}
	if (selected("flush")) {
		errno = EIO;
		return -1;
	}
	return __real_fsync(fd);
}
int __wrap_close(int fd) {
	assert(fd >= 0 && fd < 128 && active[fd]);
	active[fd] = false;
	int result = __real_close(fd);
	if (selected("close") && !injected_close++) {
		errno = EINTR;
		return -1;
	}
	if (selected("output-close") && injected_close++ == 1) {
		errno = EIO;
		return -1;
	}
	return result;
}
__attribute__((destructor)) static void verify_descriptors(void) {
	for (int fd = 0; fd < 128; fd++) {
		assert(!active[fd]);
	}
}
