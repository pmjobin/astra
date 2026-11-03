/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "../../lib/runtime/platform/files-posix.h"
#include <assert.h>
#include <errno.h>
#include <stddef.h>
int32_t astra_host_text_byte(const unsigned char *, int32_t, int32_t);

int main(void) {
	static const unsigned char text[] = {'a', 0, 255};
	assert(astra_host_text_byte(text, 3, 0) == 'a');
	assert(astra_host_text_byte(text, 3, 1) == 0);
	assert(astra_host_text_byte(text, 3, 2) == 255);
	assert(astra_host_text_byte(text, 3, 3) == -1);
	assert(astra_host_text_byte(NULL, 0, 0) == -1);
	assert(astra_host_text_byte(text, -1, 0) == -1);
	assert(astra_file_open(text, 3, 0) == -EINVAL);
	assert(astra_file_open(NULL, 1, 0) == -EINVAL);
	assert(astra_file_open(NULL, -1, 0) == -EINVAL);
	assert(astra_file_open(NULL, 0, 7) == -EINVAL);
	assert(astra_file_open(NULL, 0, 0) == -ENOENT);
	assert(astra_file_read_byte(-1) == -1 - EBADF);
	assert(astra_file_write_byte(-1, 0) == -EBADF);
	assert(astra_file_write_byte(-1, 256) == -EINVAL);
	assert(astra_file_write_byte(-1, -1) == -EINVAL);
	assert(astra_file_flush(-1) == -EBADF);
	assert(astra_file_close(-1) == -EBADF);
	return 0;
}
