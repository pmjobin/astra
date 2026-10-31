/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "../../lib/runtime/platform/args-posix.h"
#include <assert.h>
#include <string.h>

extern int args_print(const struct AstraArgsTextV0 *items, int32_t count);

int main(void) {
	for (int cycle = 0; cycle < 16; cycle++) {
		char name[32] = "invocation";
		char empty[32] = "";
		char text[32] = "\xc3\xa9 e\xcc\x81\xf0\x9f\x98\x80";
		char *original[] = {name, empty, text, NULL};
		const struct AstraArgsTextV0 *items = NULL;
		assert(astra_host_args_prepare_v0(3, original, &items) == 0);
		strcpy(name, "changed name");
		strcpy(empty, "not empty");
		strcpy(text, "changed payload");
		original[0] = text;
		original[1] = name;
		original[2] = empty;
		int result = args_print(items, 3);
		astra_host_args_dispose_v0(items);
		if (result != 0) {
			return result;
		}
	}
	return 0;
}
