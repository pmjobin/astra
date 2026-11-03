/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
extern uint64_t astra_systems_mix(uint64_t value);
_Static_assert(sizeof(uint64_t) == 8 && sizeof(void *) == 8, "qualified host ABI");

int main(int argc, char **argv) {
	if (argc != 2 || argv[1][0] == '-') {
		return 64;
	}
	char *end;
	errno = 0;
	uint64_t value = strtoull(argv[1], &end, 10);
	if (errno || *end || end == argv[1]) {
		return 64;
	}
	printf("%" PRIu64 "\n", astra_systems_mix(value));
	return 0;
}
