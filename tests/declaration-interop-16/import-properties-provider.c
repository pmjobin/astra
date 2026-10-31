/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <assert.h>
#ifdef USE_SDK
#include "imports16.h"
typedef RECORD_READING reading;
typedef RECORD_PAIR pair;
#else
typedef struct astra_foreign_error {
	int32_t domain, code;
} astra_foreign_error;
typedef struct reading {
	int32_t count;
	double scale;
	bool enabled;
} reading;
typedef struct pair {
	double first;
	int32_t second;
} pair;
#endif
typedef struct property_child16_handle {
	int32_t value;
} property_child16_handle;
typedef struct property_provider16_handle {
	unsigned references;
	int32_t mode, amount;
	uint32_t unsigned32;
	int64_t signed64;
	uint64_t unsigned64;
	float single;
	double precise;
	bool enabled;
	reading reading;
	pair pair;
	uint8_t bytes[32], title[32];
	int32_t byte_count, title_count, child;
} property_provider16_handle;
typedef struct allocation {
	uint64_t tag;
	uint8_t payload[];
} allocation;
static unsigned roots, retired, children, child_retired, allocations, releases, errors, setters;
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
static uint8_t *copy(const uint8_t *input, int32_t length) {
	assert(length >= 0);
	allocation *p = malloc(sizeof *p + (size_t)length + 1);
	assert(p);
	p->tag = UINT64_C(0x161670726f7073);
	memcpy(p->payload, input, (size_t)length);
	p->payload[length] = 0;
	++allocations;
	return p->payload;
}
static int32_t release(uint8_t **owner, int32_t *length, astra_foreign_error *error) {
	assert(owner && *owner && length);
	clear(error);
	allocation *p = (allocation *)(*owner - sizeof(allocation));
	assert(p->tag == UINT64_C(0x161670726f7073));
	p->tag = 0;
	memset(*owner, 0xdd, (size_t)*length);
	free(p);
	*owner = NULL;
	*length = 0;
	++releases;
	return 0;
}
int32_t property_provider16_bytes_release(uint8_t **owner, int32_t *length, astra_foreign_error *error) {
	return release(owner, length, error);
}
int32_t property_provider16_text_release(char **owner, int32_t *length, astra_foreign_error *error) {
	uint8_t *bytes = (uint8_t *)*owner;
	int32_t status = release(&bytes, length, error);
	*owner = (char *)bytes;
	return status;
}
int32_t properties16_error_seen(void) {
	assert(allocations == releases);
	++errors;
	return 0;
}
int32_t property_provider16_create(int32_t mode, property_provider16_handle **out, astra_foreign_error *error) {
	clear(error);
	*out = calloc(1, sizeof **out);
	assert(*out);
	(*out)->references = 1;
	(*out)->mode = mode;
	++roots;
	return 0;
}
#ifdef EXPECT_SHARED
uint32_t property_provider16_release(property_provider16_handle *self) {
	assert(self && self->references);
	unsigned n = --self->references;
	if (!n) {
		++retired;
		free(self);
	}
	return n;
}
#else
int32_t property_provider16_destroy(property_provider16_handle **owner, astra_foreign_error *error) {
	assert(owner && *owner);
	clear(error);
	free(*owner);
	*owner = NULL;
	++retired;
	return 0;
}
#endif
#define SCALAR_PROPERTY(name,type) \
int32_t property_provider16_get_##name(property_provider16_handle *self,type *out,astra_foreign_error *error){assert(self && out);clear(error);*out=self->name;return 0;} \
int32_t property_provider16_set_##name(property_provider16_handle *self,type input,astra_foreign_error *error){assert(self);clear(error);self->name=input;++setters;return 0;}
SCALAR_PROPERTY(unsigned32, uint32_t)
SCALAR_PROPERTY(signed64, int64_t)
SCALAR_PROPERTY(unsigned64, uint64_t)
SCALAR_PROPERTY(single, float)
SCALAR_PROPERTY(precise, double)
SCALAR_PROPERTY(enabled, bool)
SCALAR_PROPERTY(reading, reading)
SCALAR_PROPERTY(pair, pair)
int32_t property_provider16_get_amount(property_provider16_handle *self, int32_t *out, astra_foreign_error *error) {
	assert(self && out);
	clear(error);
	*out = self->amount;
	return 0;
}
int32_t property_provider16_set_amount(property_provider16_handle *self, int32_t input, astra_foreign_error *error) {
	assert(self);
	clear(error);
	if (input < 0) {
		return fail(error);
	}
	self->amount = input;
	++setters;
	return 0;
}
int32_t property_provider16_set_bytes(property_provider16_handle *self, const uint8_t *input, int32_t length, astra_foreign_error *error) {
	assert(self && input && length >= 0 && length <= 32);
	clear(error);
	memcpy(self->bytes, input, (size_t)length);
	self->byte_count = length;
	++setters;
	return 0;
}
int32_t property_provider16_get_bytes(property_provider16_handle *self, uint8_t **out, int32_t *length, astra_foreign_error *error) {
	assert(self && out && length);
	clear(error);
	*length = self->byte_count;
	*out = copy(self->bytes, *length);
	if (self->mode == 1) {
		return fail(error);
	}
	return 0;
}
int32_t property_provider16_set_title(property_provider16_handle *self, const char *input, int32_t length, astra_foreign_error *error) {
	assert(self && input && length == 4 && input[1] == 0);
	clear(error);
	memcpy(self->title, input, (size_t)length);
	self->title_count = length;
	++setters;
	return 0;
}
int32_t property_provider16_get_title(property_provider16_handle *self, char **out, int32_t *length, astra_foreign_error *error) {
	assert(self && out && length);
	clear(error);
	*length = self->title_count;
	*out = (char *)copy(self->title, *length);
	if (self->mode == 2) {
		(*out)[0] = (char)0xc0;
	}
	return 0;
}
int32_t property_child16_create(int32_t value, property_child16_handle **out, astra_foreign_error *error) {
	clear(error);
	*out = malloc(sizeof **out);
	assert(*out);
	(*out)->value = value;
	++children;
	return 0;
}
int32_t property_child16_destroy(property_child16_handle **owner, astra_foreign_error *error) {
	assert(owner && *owner);
	clear(error);
	free(*owner);
	*owner = NULL;
	++child_retired;
	return 0;
}
int32_t property_child16_get_code(property_child16_handle *self, int32_t *out, astra_foreign_error *error) {
	assert(self && out);
	clear(error);
	*out = self->value;
	return 0;
}
int32_t property_provider16_set_child(property_provider16_handle *self, property_child16_handle **input, astra_foreign_error *error) {
	assert(self && input && *input);
	self->child = (*input)->value;
	++setters;
	return property_child16_destroy(input, error);
}
int32_t property_provider16_get_child(property_provider16_handle *self, property_child16_handle **out, astra_foreign_error *error) {
	assert(self);
	return property_child16_create(self->child, out, error);
}
extern int32_t import_properties16_run(int32_t mode);
int main(void) {
	for (int32_t mode = 0; mode < 3; ++mode) {
		int32_t result = import_properties16_run(mode);
		if (result) {
			fprintf(stderr, "property mode %d returned %d\n", mode, result);
			return 1;
		}
		assert(roots == retired && allocations == releases && children == child_retired);
	}
	assert(roots == 3 && children == 2 && allocations == 5 && errors == 3 && setters == 33);
	puts("PASS typed C Class imported properties and exact ownership");
	return 0;
}
