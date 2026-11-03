/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
static unsigned seen[3];

void scoped_task_retired(int32_t identity) {
	if (identity < 1 || identity > 2 || seen[identity]++) abort();
}

int32_t scoped_task_finish(void) {
	if (seen[1] != 1 || seen[2] != 1) abort();
	puts("scoped record: two retained owners, two allocator instances, exact joined retirement");
	return 0;
}

int32_t scoped_record_probe(void);

int main(void) {
	return scoped_record_probe();
}
