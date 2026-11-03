/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
static unsigned retired;

void same_sync_retired(int32_t identity) {
	if (identity != 17 || retired++) abort();
}

int32_t same_sync_finish(void) {
	if (retired != 1) abort();
	return 0;
}

int32_t same_sync_probe(void);

int main(void) {
	if (same_sync_probe() != 0 || retired != 1) abort();
	puts("scoped sync error: empty carrier acquires and transfers its original payload once");
	return 0;
}
