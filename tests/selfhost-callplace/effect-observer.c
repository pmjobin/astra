// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Observable byte sink only; all target-language operations remain in Astra.
#include <unistd.h>

int callplace_effect(int value) {
	unsigned char byte = (unsigned char)value;
	return write(1, &byte, 1) == 1 ? 0 : -1;
}
