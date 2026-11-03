/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "record-api.h"
#include <stddef.h>
#include <stdio.h>
#define LAYOUT(T,last) printf(#T " size=%zu align=%zu last=%zu\n",sizeof(struct T),_Alignof(struct T),offsetof(struct T,last))

int main(void) {
	LAYOUT(RecordInts, second);
	LAYOUT(RecordFloats, second);
	LAYOUT(RecordMixed, mean);
	LAYOUT(RecordStack, tag);
	LAYOUT(RecordPadded, wide);
	return 0;
}
