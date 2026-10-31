// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#include <stdint.h>

extern void astra_test_reset(void);

int32_t astra_test_add_impl(int32_t a, int32_t b) {
	return a + b;
}

void astra_test_reset_impl(void) {
	astra_test_reset();
}

int32_t c_value(void) {
	return 42;
}
