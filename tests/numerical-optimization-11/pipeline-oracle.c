// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdio.h>
#include <stdlib.h>
static int created, destroyed, observed, failed;
static FILE *output;

void pipeline_lifetime(int event) {
	if (event == 1)
		created++;
	else if (event == 2)
		destroyed++;
	else
		failed = 1;
	if (created != 1 || destroyed > 1) failed = 1;
}

int pipeline_observe(int sequence, int value) {
	if (!sequence) {
		const char *path = getenv("ASTRA_NUMERICAL_OUTPUT");
		if (path) {
			output = fopen(path, "wb");
			if (!output) exit(72);
		}
	}
	int input = sequence % 1000;
	int expected = (sequence % 2 == 0 ? input + 3 : input * 2) + input + 5 + sequence % 23 + input + 3;
	if (observed != sequence || value != expected || created != 1 || destroyed != 0) failed = 1;
	if (output && fwrite(&value, sizeof value, 1, output) != 1) failed = 1;
	observed++;
	return failed;
}

int pipeline_finish(int count) {
	if (output && fclose(output)) failed = 1;
	if (observed != count || created != 1 || destroyed != 1) failed = 1;
	printf("numerical:A95:%d created=%d destroyed=%d failed=%d\n", observed, created, destroyed, failed);
	return failed;
}
