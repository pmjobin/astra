/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

extern int32_t astra_fn_evaluate(int32_t, int32_t);
extern int64_t astra_fn_wide(int64_t);
extern int32_t astra_fn_positive(int32_t);
extern int32_t astra_fn_answer(void);
extern int64_t astra_fn_combine(int64_t, int32_t);
extern int32_t astra_fn_qualified(int32_t);
extern double astra_fn_half(double);
extern int32_t astra_fn_exported(int32_t);
extern int32_t astra_fn_assigned(int32_t, int32_t);
extern int32_t astra_fn_four(void);
extern int32_t astra_fn_shadow(int32_t);
extern int32_t astra_fn_direct_argument(int32_t);
extern int32_t astra_fn_generic(int32_t);

/* GNU/ELF link wrapping observes the Astra object's allocation references.
 * libc-internal allocations (such as printf below) are outside this claim. */
extern void *__real_malloc(size_t);
extern void *__real_calloc(size_t, size_t);
extern void *__real_realloc(void *, size_t);
static int armed;
static unsigned allocations;
void *__wrap_malloc(size_t size) {
	if (armed) ++allocations;
	return __real_malloc(size);
}
void *__wrap_calloc(size_t count, size_t size) {
	if (armed) ++allocations;
	return __real_calloc(count, size);
}
void *__wrap_realloc(void *pointer, size_t size) {
	if (armed) ++allocations;
	return __real_realloc(pointer, size);
}

int main(void) {
	int64_t sum = 0;
	/* Establish that all three observers are active before measuring Fn. */
	armed = 1;
	void *control = malloc(1);
	void *zeroed = calloc(1, 2);
	if (control == NULL || zeroed == NULL) return 20;
	void *grown = realloc(control, 3);
	if (grown == NULL) return 21;
	free(grown);
	free(zeroed);
	armed = 0;
	if (allocations != 3) return 22;
	allocations = 0;
	armed = 1;
	for (int32_t value = -31; value <= 31; ++value) {
		for (int32_t mode = 0; mode <= 1; ++mode) {
			int32_t actual = astra_fn_evaluate(mode, value);
			int32_t expected = mode == 0 ? value + 14 : value * 9;
			if (actual != expected) return 11;
			if (astra_fn_assigned(mode, value) != (mode == 0 ? value + 7 : value * 3)) return 18;
			sum += actual;
		}
		if (astra_fn_positive(value) != (value > 0)) return 12;
		if (astra_fn_qualified(value) != 2 * value + 108) return 13;
		if (astra_fn_shadow(value) != value * 3 || astra_fn_direct_argument(value) != value + 14) return 23;
		if (astra_fn_generic(value) != value + 7) return 24;
	}
	int64_t wide = astra_fn_wide(INT64_C(4294967296));
	int64_t combined = astra_fn_combine(INT64_C(4294967296), -19);
	if (wide != INT64_C(8589934593) || combined != INT64_C(73014444013)) return 14;
	if (astra_fn_answer() != 42 || astra_fn_half(9.5) != 4.75) return 15;
	if (astra_fn_exported(7) != 106) return 17;
	if (astra_fn_four() != 85) return 19;
	armed = 0;
	if (allocations != 0) return 16;
	printf("sum=%" PRId64 " wide=%" PRId64 " combined=%" PRId64 " allocations=%u\n",
	       sum, wide, combined, allocations);
	return 0;
}
