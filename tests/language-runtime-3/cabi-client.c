// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
extern int32_t astra_record_bridge(int32_t);
extern int32_t astra_callback_bridge(int32_t);

int main(int argc, char **argv) {
	if (argc != 2) return 64;
	int32_t seed = (int32_t)strtol(argv[1], NULL, 10);
#ifdef CABI_RECORD
	int32_t result = astra_record_bridge(seed);
	if (!result) printf("record:%d:72:8\n", seed);
#else
	int32_t result = astra_callback_bridge(seed);
	if (!result) printf("callback:%d:%lld:6:2\n", seed, (long long)(154 + (int64_t)seed * 6));
#endif
	return result;
}
