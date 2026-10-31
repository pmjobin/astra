/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
extern int64_t surge_shipment_total(int32_t, int32_t);
int main(int argc, char **argv) {
	if (argc != 3) return 64;
	int32_t price = (int32_t)strtol(argv[1], NULL, 10);
	int32_t count = (int32_t)strtol(argv[2], NULL, 10);
	printf("shipment=%" PRId64 "\n", surge_shipment_total(price, count));
	return 0;
}
