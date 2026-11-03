/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "a122-packets.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>

struct PacketReader {
	FILE *file;
	int32_t expected, consumed, kind, failed;
};

static int opened, closed, callbacks;

static int setting(const char *name) {
	const char *s = getenv(name);
	return s ? atoi(s) : 0;
}

PacketReader *a122_open(void) {
	if (setting("A122_ALLOC_FAIL")) return NULL;
	PacketReader *r = calloc(1, sizeof(*r));
	if (!r) return NULL;
	const char *path = getenv("A122_INPUT");
	r->file = path ? fopen(path, "rb") : NULL;
	if (!r->file) {
		free(r);
		return NULL;
	}
	++opened;
	return r;
}

void a122_close(PacketReader *r) {
	if (!r) return;
	if (fclose(r->file) != 0) abort();
	++closed;
	memset(r, 0xa5, sizeof(*r));
	free(r);
}

int32_t a122_header(PacketReader *r, int32_t *magic, int32_t *count) {
	unsigned char bytes[6];
	if (!r || !magic || !count) return -1;
	*magic = 0;
	*count = 0;
	if (fread(bytes, 1, sizeof(bytes), r->file) != sizeof(bytes)) return r->failed = -1;
	*magic = (int32_t)bytes[0] | ((int32_t)bytes[1] << 8);
	*count = (int32_t)bytes[2] | ((int32_t)bytes[3] << 8);
	if (bytes[4] != 1 || bytes[5] != 0) return r->failed = -1;
	r->expected = *count;
	return 0;
}

int32_t a122_kind(PacketReader *r) {
	if (!r || r->failed) return -1;
	r->kind = fgetc(r->file);
	return r->kind;
}

static uint64_t payload(PacketReader *r, int expected) {
	unsigned char bytes[8];
	if (!r || r->kind != expected || fread(bytes, 1, 8, r->file) != 8) {
		if (r) r->failed = -1;
		return 0;
	}
	uint64_t value = 0;
	for (unsigned i = 0; i < 8; ++i)
		value |= (uint64_t)bytes[i] << (8 * i);
	++r->consumed;
	return value;
}

A122Packet a122_signed(PacketReader *r) {
	uint64_t bits = payload(r, 1);
	A122Packet result = {1, {.integer = 0}};
	memcpy(&result.payload.integer, &bits, sizeof(bits));
	return result;
}

A122Packet a122_unsigned(PacketReader *r) {
	A122Packet result = {2, {.bits = payload(r, 2)}};
	return result;
}

int32_t a122_status(PacketReader *r) {
	return r ? r->failed : -1;
}

bool a122_complete(PacketReader *r) {
	return r && !r->failed && r->consumed == r->expected && fgetc(r->file) == EOF && !ferror(r->file);
}

int32_t a122_apply(int32_t (*callback)(A122Stats *, int32_t), A122Stats *stats, int32_t ordinal) {
	if (!callback || !stats || stats->count != ordinal - 1) abort();
	++callbacks;
	int32_t result = callback(stats, ordinal);
	if (stats->count != ordinal || stats->last != ordinal || stats->total != (int64_t)ordinal * (ordinal + 1) / 2) abort();
	return result;
}

int32_t a122_finish(int32_t result) {
	int expected = setting("A122_EXPECT");
	int owners = setting("A122_OWNERS");
	if (result != expected || opened != owners || closed != owners || callbacks != setting("A122_CALLBACKS")) {
		fprintf(stderr, "A122 mismatch: result=%" PRId32 "/%d opened=%d closed=%d owners=%d callbacks=%d\n", result, expected, opened, closed, owners, callbacks);
		return 90;
	}
	printf("PASS A122: status=%" PRId32 " opened=%d closed=%d callbacks=%d\n", result, opened, closed, callbacks);
	return 0;
}
