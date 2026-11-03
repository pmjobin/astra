// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
static int identity;

void *token(void) {
	return &identity;
}
