/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stddef.h>
#include <stdint.h>
#include <string.h>

struct RecordLeaf {
	uint8_t tag;
	uint64_t value;
};

struct RecordPair {
	uint8_t first;
	struct RecordLeaf leaf;
	uint8_t last;
};

struct RecordCarrier {
	uint8_t first;
	uint8_t tag;
	uint64_t value;
	uint8_t last;
};

_Static_assert(sizeof(struct RecordPair) == 32, "original nested memory ABI");
_Static_assert(sizeof(struct RecordCarrier) == 24, "original flat carrier ABI");
extern int record_roundtrip(const struct RecordPair *source, struct RecordPair *destination);

int main(void) {
	struct RecordPair source = {2, {1, UINT64_C(1234605616436508552)}, 3};
	struct RecordPair destination;
	memset(&destination, 165, sizeof(destination));
	if (record_roundtrip(&source, &destination) != 42 || destination.first != 2 || destination.leaf.tag != 1 || destination.leaf.value != source.leaf.value || destination.last != 3) return 2;
	unsigned char occupied[sizeof(destination)] = {0};
	occupied[offsetof(struct RecordPair, first)] = 1;
	occupied[offsetof(struct RecordPair, leaf) + offsetof(struct RecordLeaf, tag)] = 1;
	for (size_t i = 0; i < sizeof(destination.leaf.value); ++i)
		occupied[offsetof(struct RecordPair, leaf) + offsetof(struct RecordLeaf, value) + i] = 1;
	occupied[offsetof(struct RecordPair, last)] = 1;
	const unsigned char *bytes = (const unsigned char *)&destination;
	for (size_t i = 0; i < sizeof(destination); ++i)
		if (!occupied[i] && bytes[i] != 165) return 3;
	return 42;
}
