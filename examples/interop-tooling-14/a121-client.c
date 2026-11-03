/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "a121.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

static int closed;

int32_t a121_quota_closed(int32_t capacity, int32_t used) {
	if ((closed == 0 && (capacity != 100 || used != 5)) ||
	    (closed == 1 && (capacity != 23 || used != 4))) abort();
	++closed;
	return 0;
}

extern int32_t a121_native_work(void);

int main(void) {
	a121_quota_handle *service = a121_quota_create(100);
	if (!service || a121_quota_root_identity(service) == 0) return 1;
	int32_t value = -1;
	if (a121_quota_get(service, &value) != 0 || value != 100) return 2;
	if (a121_quota_set(service, 30) != 0 || a121_quota_get(service, &value) != 0 || value != 70) return 3;
	if (a121_quota_set(service, 101) != 0 || a121_quota_get(service, &value) != 0 || value != 70) return 4;
	if (a121_quota_set(service, -1) != 0 || a121_quota_get(service, &value) != 0 || value != 70) return 5;
	a121_quota_weak_handle *weak = a121_quota_weak(service);
	if (!weak || a121_quota_acquire(service) != 2) return 6;
	a121_quota_handle *view = a121_quota_weak_upgrade(weak);
	if (view != service || a121_quota_root_identity(view) != a121_quota_root_identity(service)) return 7;
	if (a121_quota_release(service) != 2 || a121_quota_release(view) != 1) return 8;
	if (a121_quota_set(service, 5) != 0) return 9;
	if ((uint32_t)a121_quota_get(service, NULL) != UINT32_C(0x80004003)) return 10;
	if (a121_quota_release(service) != 0 || closed != 1) return 11;
	if (a121_quota_weak_upgrade(weak) != NULL) return 12;
	a121_quota_weak_release(weak);
	if (a121_native_work() != 0 || closed != 2) return 13;
	puts("PASS A121: quota admission, denied requests, C/native aliases, weak expiry; two payloads each closed once");
	return 0;
}
