// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

void allocation_example_failure(int32_t code, int32_t count) {
	fprintf(stderr, "allocation example: failure %d (records %d)\n", code, count);
	exit(2);
}
void allocation_example_report(int32_t count, const unsigned char *file, int32_t file_length, int32_t line, const unsigned char *expression, int32_t expression_length) {
	fprintf(stderr, "allocation example: %.*s:%d: %.*s = %d\n", file_length, file, line, expression_length, expression, count);
}
