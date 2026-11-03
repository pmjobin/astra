// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdint.h>
#include <stdio.h>

static struct {
	void *address;
	int tag, dead;
} identities[64];

static int count, probes, deaths[64], deceased;

int32_t field_event(int32_t stage, int32_t tag) {
	printf("%c%d ", stage == 1 ? 'I' : stage == 2 ? 'D'
	                               : stage == 3   ? 'P'
	                                              : 'E',
	       tag);
	return 0;
}

// Independent IR bridges observe actual receiver pointers, without changing
// storage, owner transfer, field loads/stores, destruction or allocation.
void field_born(void *address, int32_t tag) {
	assert(address != NULL && count < 64);
	for (int i = 0; i < count; i++) {
		assert(identities[i].address != address || identities[i].dead);
	}
	identities[count].address = address;
	identities[count].tag = tag;
	count++;
}

void field_probe(void *address, int32_t tag) {
	int found = 0;
	for (int i = 0; i < count; i++) {
		if (!identities[i].dead && identities[i].address == address) {
			assert(identities[i].tag == tag);
			found++;
		}
	}
	assert(found == 1);
	probes++;
}

void field_dying(void *address) {
	int found = 0;
	for (int i = 0; i < count; i++) {
		if (!identities[i].dead && identities[i].address == address) {
			identities[i].dead = 1;
			deaths[deceased++] = identities[i].tag;
			found++;
		}
	}
	assert(found == 1);
}

int32_t field_done(void) {
	for (int i = 0; i < count; i++) {
		assert(identities[i].dead);
	}
	printf("probes=%d deaths=", probes);
	for (int i = 0; i < deceased; i++) {
		printf("%d,", deaths[i]);
	}
	putchar('\n');
	return 42;
}
