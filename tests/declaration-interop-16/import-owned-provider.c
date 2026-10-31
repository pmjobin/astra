/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <assert.h>
#ifdef USE_SDK
#include "imports16.h"
#else
typedef struct astra_foreign_error {
	int32_t domain, code;
} astra_foreign_error;
#endif
typedef struct owned_provider16_handle {
	unsigned references;
} owned_provider16_handle;
/* Payload address deliberately differs from the allocator's address. */
typedef struct payload {
	uint64_t magic;
	size_t extent;
	unsigned char bytes[];
} payload;
static unsigned roots, root_retired, allocations, releases, release_calls, exceptions, calls;
static int deny;
void *__real_calloc(size_t, size_t);
void *__wrap_calloc(size_t count, size_t size) {
	if (deny > 0 && --deny == 0) {
		return NULL;
	}
	return __real_calloc(count, size);
}
int32_t owned16_exception_retired(void) {
	++exceptions;
	return 0;
}
int32_t owned16_error_seen(void) {
	assert(allocations == releases);
	return 0;
}
static void clear(astra_foreign_error *error) {
	assert(error);
	error->domain = 0;
	error->code = 0;
}
static int32_t fail(astra_foreign_error *error) {
	error->domain = 16;
	error->code = -1600;
	return -1600;
}
static unsigned char *make(const unsigned char *input, size_t count) {
	payload *p = malloc(sizeof *p + count + 1);
	assert(p);
	p->magic = UINT64_C(0x165a6f776e656400);
	p->extent = count + 1;
	if (count) {
		memcpy(p->bytes, input, count);
	}
	p->bytes[count] = 0;
	++allocations;
	return p->bytes;
}
static int32_t retire(unsigned char **owner, int32_t *length, astra_foreign_error *error) {
	assert(owner && length);
	clear(error);
	++release_calls;
	if (*owner) {
		payload *p = (payload *)((unsigned char *)*owner - sizeof(payload));
		assert(p->magic == UINT64_C(0x165a6f776e656400));
		memset(p->bytes, 0xdd, p->extent);
		p->magic = 0;
		free(p);
		++releases;
	}
	*owner = NULL;
	*length = 0;
	return 0;
}
int32_t owned_provider16_bytes_release(uint8_t **owner, int32_t *length, astra_foreign_error *error) {
	return retire(owner, length, error);
}
int32_t owned_provider16_text_release(char **owner, int32_t *length, astra_foreign_error *error) {
	unsigned char *p = (unsigned char *)*owner;
	int32_t status = retire(&p, length, error);
	*owner = (char *)p;
	return status;
}
int32_t owned_provider16_create(owned_provider16_handle **out, astra_foreign_error *error) {
	clear(error);
	*out = malloc(sizeof **out);
	assert(*out);
	(*out)->references = 1;
	++roots;
	return 0;
}
#ifdef EXPECT_SHARED
uint32_t owned_provider16_release(owned_provider16_handle *self) {
	if (!self) {
		return 0;
	}
	unsigned n = --self->references;
	if (!n) {
		++root_retired;
		free(self);
	}
	return n;
}
#else
int32_t owned_provider16_destroy(owned_provider16_handle **owner, astra_foreign_error *error) {
	clear(error);
	assert(owner && *owner);
	++root_retired;
	free(*owner);
	*owner = NULL;
	return 0;
}
#endif
int32_t owned_provider16_bytes(owned_provider16_handle *self, int32_t mode, const uint8_t *input, int32_t length, uint8_t *output, int32_t capacity, int32_t *count, uint8_t **out, int32_t *out_length, astra_foreign_error *error) {
	assert(self && input && length == 3 && input[0] == 1 && output && capacity == 4 && count && out && out_length);
	++calls;
	clear(error);
	output[0] = 11;
	output[1] = 12;
	*count = 2;
	const unsigned char bytes[] = {21, 0, 195, 169};
	*out_length = 4;
	*out = NULL;
	if (mode != 3 && mode != 7) {
		*out = make(bytes, 4);
	}
	if (mode == 1) {
		return fail(error);
	}
	if (mode == 2) {
		*out_length = -1;
	}
	if (mode == 4 || mode == 7) {
		*out_length = 0;
	}
	if (mode == 5) {
		deny = 1;
	}
	if (mode == 6) {
		return 2;
	}
	if (mode == 8) {
		error->domain = 16;
		error->code = -1600;
	}
	return 0;
}
int32_t owned_provider16_counted(owned_provider16_handle *self, int32_t mode, char **out, int32_t *length, astra_foreign_error *error) {
	assert(self && out && length);
	clear(error);
	unsigned char bytes[] = {97, 0, 195, 169};
	*length = 4;
	if (mode == 1) {
		bytes[0] = 192;
		bytes[1] = 175;
	}
	if (mode == 2) {
		*length = 3;
	}
	if (mode == 3) {
		bytes[0] = 237;
		bytes[1] = 160;
		bytes[2] = 128;
	}
	if (mode == 5) {
		*length = 0;
	}
	*out = (char *)make(bytes, 4);
	if (mode == 4) {
		return fail(error);
	}
	return 0;
}
int32_t owned_provider16_nul(owned_provider16_handle *self, int32_t mode, char **out, int32_t *length, astra_foreign_error *error) {
	assert(self && out && length);
	clear(error);
	unsigned char bytes[] = {99, 97, 102, 195, 169};
	*length = 5;
	if (mode == 1) {
		bytes[1] = 0;
	}
	if (mode == 3) {
		bytes[3] = 192;
	}
	*out = (char *)make(bytes, 5);
	if (mode == 2) {
		(*out)[5] = 'x';
	}
	return 0;
}
extern int32_t import_owned16_run(int32_t mode);
int main(void) {
	for (int32_t mode = 0; mode < 11; ++mode) {
		deny = mode == 9 ? 1 : mode == 10 ? 2
		                                  : 0;
		int32_t result = import_owned16_run(mode);
		if (result) {
			fprintf(stderr, "owned mode %d returned %d\n", mode, result);
			return 1;
		}
		assert(allocations == releases && roots == root_retired);
	}
	assert(roots == 11 && calls == 9 && allocations == 17 && releases == 17 && release_calls == 19 && exceptions == 15);
	puts("PASS typed C Class imports and matching owned byte/text release");
	return 0;
}
