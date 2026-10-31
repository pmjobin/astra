// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include "counter.h"
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

static unsigned fail_after;
static unsigned constructed;
static unsigned destroyed;
static unsigned bad;
void *__real_calloc(size_t count, size_t bytes);
void *__wrap_calloc(size_t count, size_t bytes) {
	if (fail_after && --fail_after == 0) return NULL;
	return __real_calloc(count, bytes);
}
int32_t counter14_created(int32_t value) { if (value != 40) ++bad; ++constructed; return 0; }
int32_t counter14_destroyed(int32_t value) { if (value != 40) ++bad; ++destroyed; return 0; }
#define CHECK(condition) do { if (!(condition)) { printf("FAIL allocation line=%d: %s\n", __LINE__, #condition); return 1; } } while (0)
int main(void) {
	/* Failure before initialization has no payload to destroy. */
	fail_after = 1;
	CHECK(counter14_create(40) == NULL && constructed == 0 && destroyed == 0);
	/* Failure after construction must retire the native strong root once. */
	fail_after = 2;
	CHECK(counter14_create(40) == NULL && constructed == 1 && destroyed == 1);
	counter14_handle *root = counter14_create(40);
	CHECK(root && constructed == 2 && destroyed == 1);
	fail_after = 1;
	CHECK(counter14_weak(root) == NULL);
	counter14_weak_handle *weak = counter14_weak(root);
	CHECK(weak);
	fail_after = 1;
	CHECK(counter14_weak_clone(weak) == NULL);
	/* Failed weak allocations must not retain either count. */
	CHECK(counter14_release(root) == 0 && destroyed == 2);
	CHECK(counter14_weak_upgrade(weak) == NULL);
	counter14_weak_release(weak);
	CHECK(bad == 0);
	puts("PASS opaque C Class allocation failures: root, control, weak and weak clone; exact partial cleanup");
	return 0;
}
