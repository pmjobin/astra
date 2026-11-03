// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdint.h>
extern int32_t exported(int32_t value);

double sources_double(double x) {
	return x * 2.0;
}

float sources_float(float x) {
	return x + 1.0f;
}

int32_t sources_call_export(int32_t value) {
	return exported(value);
}
