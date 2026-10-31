/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_FILES_POSIX_H
#define ASTRA_FILES_POSIX_H
#include <stdint.h>
/* Read-only noescape counted UTF-8 path; NUL rejected. mode 0 read, 1 truncate.
 * Open returns fd>=0 or -errno. Read returns octet, -1 EOF, or -1-errno.
 * Scalar write/flush/close return 0 or -errno. No function retains a source pointer. */
int32_t astra_file_open(const unsigned char *path, int32_t length, int32_t mode);
int32_t astra_file_read_byte(int32_t descriptor);
int32_t astra_file_write_byte(int32_t descriptor, int32_t byte);
/* Synchronous borrowed octets: the complete live view has I32 length;
 * offset/count select a validated subrange. No pointer is retained. One
 * bounded syscall (apart from EINTR retries), returning progress or -errno.
 * A nonempty write returning zero is reported as -EIO. */
int32_t astra_file_read_buffer(int32_t descriptor, unsigned char *data, int32_t length, int32_t offset, int32_t count);
int32_t astra_file_write_buffer(int32_t descriptor, const unsigned char *data, int32_t length, int32_t offset, int32_t count);
int32_t astra_file_write_text(int32_t descriptor, const unsigned char *data, int32_t length, int32_t offset, int32_t count);
int32_t astra_file_flush(int32_t descriptor);
int32_t astra_file_close(int32_t descriptor);
#endif
