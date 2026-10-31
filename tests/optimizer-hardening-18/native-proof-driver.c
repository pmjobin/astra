/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "native-proof.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Qualification adapter only; no application implementation or object execution. */
int main(int argc, char **argv) {
	if (argc < 6) return 2;
	FILE *file = fopen(argv[1], "rb");
	if (!file || fseek(file, 0, SEEK_END)) return 2;
	long length = ftell(file);
	if (length < 0 || length > 128 * 1024 * 1024 || fseek(file, 0, SEEK_SET)) return 2;
	unsigned char *data = malloc((size_t)length + 1);
	if (!data || fread(data, 1, (size_t)length, file) != (size_t)length || fclose(file)) return 2;
	unsigned types[16];
	int count = 0;
	int next = 5;
	for (; next < argc && strcmp(argv[next], "--"); next++) {
		if (count == 16) return 2;
		types[count++] = (unsigned)strtoul(argv[next], NULL, 10);
	}
	char *symbols[16], *contracts[16];
	int callees = 0;
	if (next < argc) next++;
	for (; next < argc; next += 2) {
		if (callees == 16 || next + 1 >= argc) return 2;
		symbols[callees] = argv[next];
		contracts[callees++] = argv[next + 1];
	}
	unsigned offset = (unsigned)strtoul(argv[3], NULL, 10), size = (unsigned)strtoul(argv[4], NULL, 10);
	/* The first supplied type is the result; the remaining types are formals. */
	if (!count) return 2;
	unsigned proof = astra_native_object_proof(data, (int)length, argv[2], types + 1, count - 1, types[0], &offset, 1, &size, 1, symbols, callees, contracts, callees);
	free(data);
	printf("%u\n", proof);
	return 0;
}
