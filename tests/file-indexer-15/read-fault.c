/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/* Test-only transport fault. The real POSIX adapter still performs reads;
 * indexing, rollback, cache decisions and retry remain entirely in Astra. */
extern int32_t astra_real_file_read_buffer(int32_t, unsigned char *, int32_t, int32_t, int32_t);
static int configured;
static int fired;
static int64_t limit = -1;
static int64_t progress;

int32_t astra_file_read_buffer(int32_t fd, unsigned char *data, int32_t length,
                               int32_t offset, int32_t count) {
	if (!configured) {
		configured = 1;
		const char *value = getenv("ASTRA_INDEX_READ_FAIL_AFTER");
		if (value) {
			char *end;
			errno = 0;
			long parsed = strtol(value, &end, 10);
			if (errno || !*value || *end || parsed < 0 || parsed > INT32_MAX) {
				abort();
			}
			limit = parsed;
		}
	}
	if (!fired && limit >= 0 && count > 0) {
		if (progress == limit) {
			fired = 1;
			fprintf(stderr, "index-read-fault\t%lld\n", (long long)progress);
			return -EIO;
		}
		if ((int64_t)count > limit - progress) {
			count = (int32_t)(limit - progress);
		}
	}
	int32_t result = astra_real_file_read_buffer(fd, data, length, offset, count);
	if (result > 0) {
		progress += result;
	}
	return result;
}
