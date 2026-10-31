/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdio.h>
int main(void) {
	fputs("S:", stdout);
	for (int block = 0; block < 4; ++block) {
		double previous = 0.0, total = 0.0;
		for (int i = 0; i < 32; ++i) {
			double input = (double)((block * 32 + i) % 9 + 1) / 16.0;
			double filtered = previous * 0.5 + input * 0.25;
			previous = filtered;
			total += filtered;
		}
		printf("%06d,", (int)(total * 1024.0));
	}
	puts("D");
	return 0;
}
