/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "../../lib/runtime/platform/files-posix.h"
#include <assert.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>
int main(void) {
	unsigned char data[8] = {7, 7, 7, 7, 7, 7, 7, 7};
	assert(astra_file_read_buffer(-1, data, 8, 0, 8) == -EBADF);
	assert(astra_file_write_buffer(-1, data, 8, 0, 8) == -EBADF);
	assert(astra_file_read_buffer(-1, NULL, 1, 0, 1) == -EINVAL);
	assert(astra_file_write_buffer(-1, NULL, 1, 0, 1) == -EINVAL);
	assert(astra_file_read_buffer(-1, data, -1, 0, 0) == -EINVAL);
	assert(astra_file_write_buffer(-1, data, 8, -1, 0) == -EINVAL);
	assert(astra_file_read_buffer(-1, data, 8, 9, 0) == -EINVAL);
	assert(astra_file_write_buffer(-1, data, 8, 7, 2) == -EINVAL);
	assert(astra_file_read_buffer(-1, NULL, 0, 0, 0) == 0);
	assert(astra_file_write_buffer(-1, NULL, 0, 0, 0) == 0);
	assert(astra_file_read_buffer(-1, data, 0, 0, 0) == 0);
	assert(astra_file_write_buffer(-1, data, 0, 0, 0) == 0);
	assert(astra_file_read_buffer(-1, data, 8, 8, 0) == 0);
	int pair[2];
	assert(pipe(pair) == 0);
	const unsigned char payload[] = {0, 255, 128};
	assert(astra_file_write_buffer(pair[1], payload, 3, 0, 3) == 3);
	assert(close(pair[1]) == 0);
	assert(astra_file_read_buffer(pair[0], data, 8, 2, 6) == 3);
	assert(data[0] == 7 && data[1] == 7 && data[5] == 7 && data[6] == 7 && data[7] == 7);
	assert(memcmp(data + 2, payload, 3) == 0);
	assert(astra_file_read_buffer(pair[0], data, 8, 0, 8) == 0);
	assert(close(pair[0]) == 0);
	return 0;
}
