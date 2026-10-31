/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef A122_PACKETS_H
#define A122_PACKETS_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#define A122_MAGIC ((0x41 << 8) | 0x32)
#define A122_LIMIT (2 * 8)
typedef struct PacketReader PacketReader;
typedef union {
	int64_t integer;
	uint64_t bits;
} A122Word;
typedef struct {
	int64_t tag;
	A122Word payload;
} A122Packet;
typedef struct {
	int64_t total;
	int32_t count, last;
} A122Stats;
_Static_assert(sizeof(A122Word) == 8 && _Alignof(A122Word) == 8, "union layout");
_Static_assert(sizeof(A122Packet) == 16 && offsetof(A122Packet, payload) == 8, "tagged layout");
_Static_assert(sizeof(A122Stats) == 16 && offsetof(A122Stats, count) == 8 && offsetof(A122Stats, last) == 12, "POD layout");
PacketReader *a122_open(void);
void a122_close(PacketReader *);
int32_t a122_header(PacketReader *, int32_t *, int32_t *);
int32_t a122_kind(PacketReader *);
A122Packet a122_signed(PacketReader *);
A122Packet a122_unsigned(PacketReader *);
int32_t a122_status(PacketReader *);
bool a122_complete(PacketReader *);
int32_t a122_apply(int32_t (*)(A122Stats *, int32_t), A122Stats *, int32_t);
int32_t a122_finish(int32_t);
#endif
