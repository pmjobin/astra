// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Runtime input and independent scalar oracle only.
#include <stdio.h>
#include <stdlib.h>

int dispatch18_input(int index) {
	const char *text = getenv("DISPATCH18_SEED");
	char *end;
	long seed = text ? strtol(text, &end, 10) : 0;
	if (text && (*end || seed < -100 || seed > 100)) abort();
	return (int)seed + index * 17 - 31;
}

int dispatch18_check(int index, int value) {
	int input = dispatch18_input(index), first = index % 2 == 0;
	int pair = 2 * input + 20;
	int join = 2 * input + (first ? 28 : 29);
	int mixed = first ? input + 11 : 2 * input;
	int dynamic = first ? input + 13 : 3 * input;
	int property = first ? input + 36 : 36;
	int expected = pair + join + mixed + dynamic + property;
	if (value == expected) return 0;
	fprintf(stderr, "index=%d actual=%d expected=%d\n", index, value, expected);
	return 1;
}
