/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
static int32_t created;
static int32_t retired;

int32_t astra_reconciliation_observe(int32_t operation) {
	switch (operation) {
	case 1:
		return ++created;
	case 2:
		return ++retired;
	case 3:
		return created - retired;
	case 4:
		return created;
	case 5:
		return retired;
	default:
		return -1;
	}
}
