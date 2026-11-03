/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern int32_t opaque_channel16_run(void);
extern int32_t go16_destroyed_count(void);
extern int32_t go16_item_destroyed_count(void);

int main(void) {
	int32_t result = opaque_channel16_run();
	if (result) {
		fprintf(stderr, "native opaque channel result %d\n", result);
		return 1;
	}
	assert(go16_destroyed_count() == 1 && go16_item_destroyed_count() == 1);
	puts("PASS opaque owned/checked properties, scalar pointees and closed record calls");
	return 0;
}
