// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
static int32_t active;
void *nonnull_acquire(int32_t value) {
	if (!value) return NULL;
	int32_t *cell = malloc(sizeof *cell);
	if (cell) {
		*cell = value;
		++active;
	}
	return cell;
}
void nonnull_release(void *value) {
	if (value) {
		assert(active > 0);
		--active;
		free(value);
	}
}
int32_t nonnull_id(void *value) {
	assert(value);
	return *(int32_t *)value;
}
int32_t nonnull_live(void) {
	return active;
}
