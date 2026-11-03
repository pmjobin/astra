// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdio.h>
extern int astra_ns_4_Left_8_identity(int);
extern int astra_ns_5_Right_8_identity(int);

int main(void) {
	int first = astra_ns_4_Left_8_identity(31);
	int second = astra_ns_5_Right_8_identity(25);
	if (first != 42 || second != 42) return 1;
	puts("namespace C exports: 42 42");
	return 0;
}
