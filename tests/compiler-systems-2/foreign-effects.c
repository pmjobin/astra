/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdint.h>
extern int32_t astra_foreign_effect(int32_t);
extern int __real_abs(int);
static int effects;
void clear_foreign_effects(void) {
	effects = 0;
}
int foreign_effect_count(void) {
	return effects;
}
int __wrap_abs(int value) {
	effects++;
	return __real_abs(value);
}
int main(void) {
	return astra_foreign_effect(-7) != 1 || astra_foreign_effect(42) != 1;
}
