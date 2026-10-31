/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static uint32_t number(FILE *file) {
	unsigned char bytes[4];
	if (fread(bytes, 1, 4, file) != 4) {
		exit(125);
	}
	return (uint32_t)bytes[0] | (uint32_t)bytes[1] << 8 | (uint32_t)bytes[2] << 16 | (uint32_t)bytes[3] << 24;
}

/* Exact byte vector input. Exit 125 and an exec diagnostic distinguish a
 * launcher/exec failure from the executed application's preparation status. */
int main(int argc, char **argv) {
	if (argc != 3) {
		return 125;
	}
	FILE *file = fopen(argv[2], "rb");
	if (file == NULL) {
		return 125;
	}
	uint32_t count = number(file);
	if (count > 1000000) {
		return 125;
	}
	char **arguments = calloc((size_t)count + 1, sizeof(char *));
	if (arguments == NULL) {
		return 125;
	}
	for (uint32_t i = 0; i < count; i++) {
		uint32_t length = number(file);
		arguments[i] = malloc((size_t)length + 1);
		if (arguments[i] == NULL || fread(arguments[i], 1, length, file) != length || memchr(arguments[i], 0, length) != NULL) {
			return 125;
		}
		arguments[i][length] = 0;
	}
	fclose(file);
	char *environment[] = {NULL};
	execve(argv[1], arguments, environment);
	perror("args test launcher execve");
	return 125;
}
