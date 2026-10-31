// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdio.h>
#include <math.h>
void usability_event(int value) {
	printf("%d\n", value);
}
double usability_nan(void) {
	return NAN;
}
double usability_infinity(void) {
	return INFINITY;
}
