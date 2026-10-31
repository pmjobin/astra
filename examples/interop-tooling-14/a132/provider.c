/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "allocation-12.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <pthread.h>
static _Atomic int created, closed, roots, retired_roots, live_fds[16], opened, retired_fds, bad;
static _Atomic int root_samples = -1;
static _Atomic int worker_records;
static pthread_t main_thread, region_thread;
static _Atomic int64_t created_sum, closed_sum;
static _Atomic(AstraAlloc12Domain *) region;
static void retain_fd(int32_t fd) {
	if (fd < 0) return;
	for (int i = 0; i < 16; ++i) {
		int empty = 0;
		if (atomic_compare_exchange_strong(&live_fds[i], &empty, fd + 1)) {
			++opened;
			return;
		}
	}
	abort();
}
int32_t a132_real_astra_net_socket(int32_t);
int32_t a132_real_astra_net_accept(int32_t);
int32_t a132_real_astra_net_close(int32_t);
int32_t astra_net_socket(int32_t kind) {
	int32_t fd = a132_real_astra_net_socket(kind);
	retain_fd(fd);
	return fd;
}
int32_t astra_net_accept(int32_t listener) {
	int32_t fd = a132_real_astra_net_accept(listener);
	retain_fd(fd);
	return fd;
}
int32_t astra_net_close(int32_t fd) {
	if (fd >= 0) {
		int found = 0;
		for (int i = 0; i < 16; ++i) {
			int expected = fd + 1;
			if (atomic_compare_exchange_strong(&live_fds[i], &expected, 0)) {
				found = 1;
				++retired_fds;
				break;
			}
		}
		if (!found) ++bad;
	}
	return a132_real_astra_net_close(fd);
}
void *a132_real_astra_alloc12_allocate(AstraAlloc12Domain *, uint64_t, uint64_t, uint32_t, uint64_t);
void *astra_alloc12_allocate(AstraAlloc12Domain *domain, uint64_t count, uint64_t extent, uint32_t alignment, uint64_t tag) {
	if (!domain || domain->kind != ASTRA_ALLOC12_REGION || alignment != 64 || count != 1) ++bad;
	AstraAlloc12Domain *previous = atomic_exchange(&region, domain);
	if (previous && previous != domain) ++bad;
	if (!previous)
		region_thread = pthread_self();
	else if (!pthread_equal(region_thread, pthread_self()))
		++bad;
	return a132_real_astra_alloc12_allocate(domain, count, extent, alignment, tag);
}
int32_t a132_ready(int32_t tcp, int32_t udp) {
	printf("READY A132 %d %d\n", tcp, udp);
	fflush(stdout);
	return 0;
}
int32_t a132_event(int32_t phase, int32_t kind, int32_t value) {
	if (kind == 100) {
		if (phase == 1) {
			++roots;
			main_thread = pthread_self();
		} else {
			if (phase != 0) ++bad;
			++retired_roots;
			root_samples = value;
		}
		return 0;
	}
	if (kind != 1 || (phase != 0 && phase != 1)) abort();
	if (!pthread_equal(region_thread, pthread_self())) ++bad;
	if (phase == 1) {
		++created;
		atomic_fetch_add(&created_sum, value);
		if (!pthread_equal(main_thread, pthread_self())) ++worker_records;
	} else {
		++closed;
		atomic_fetch_add(&closed_sum, value);
	}
	return 0;
}
static int setting(const char *name) {
	const char *value = getenv(name);
	return value ? atoi(value) : 0;
}
int32_t a132_finish(int32_t status, int32_t count, int32_t total) {
	int expected_status = setting("A132_STATUS"), wanted = expected_status == 0 ? 8 : 0;
	int expected_total = setting("A132_TOTAL");
	AstraAlloc12Domain *domain = atomic_load(&region);
	if (status != expected_status || count != wanted || total != expected_total || created != wanted || closed != wanted ||
	    created_sum != expected_total || closed_sum != expected_total || worker_records != wanted || roots != 1 || retired_roots != 1 || root_samples != wanted || opened != 3 || retired_fds != 3) ++bad;
	for (int i = 0; i < 16; ++i)
		if (atomic_load(&live_fds[i])) ++bad;
	if (wanted && (!domain || domain->live || domain->used || domain->allocations != 8 || domain->releases != 8 || domain->peak_live != 8)) ++bad;
	if (!wanted && domain) ++bad;
	if (bad) {
		fprintf(stderr, "FAIL A132: status=%d/%d samples=%d/%d sum=%d/%d records=%d/%d roots=%d/%d fds=%d/%d errors=%d\n",
		        status, expected_status, count, wanted, total, expected_total, created, closed, roots, retired_roots, opened, retired_fds, bad);
		return 90;
	}
	printf("PASS A132: provider=posix-threaded status=%d samples=%d sum=%d region-retired=%d Shared-Monitor-root-retired=1 descriptors-retired=3\n", status, count, total, closed);
	return 0;
}
