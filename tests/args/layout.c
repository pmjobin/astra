/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "../../lib/runtime/platform/args-posix.h"
#include <limits.h>
#include <stddef.h>
#include <stdio.h>

int main(void) {
	printf("{\"pointer_bytes\":%zu,\"char_bits\":%d,\"int_bytes\":%zu,\"int_max\":%d,\"data_offset\":%zu,\"length_offset\":%zu,\"stride\":%zu,\"alignment\":%zu}\n", sizeof(void *), CHAR_BIT, sizeof(int), INT_MAX, offsetof(struct AstraArgsTextV0, data), offsetof(struct AstraArgsTextV0, byte_length), sizeof(struct AstraArgsTextV0), _Alignof(struct AstraArgsTextV0));
	return 0;
}
