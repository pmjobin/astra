/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "linux.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned submissions, closes, scans, completions;
static int scan_bytes, scan_checksum;

void astra_payload_test_submitted(void) {
	submissions++;
}

void astra_payload_test_closed(void) {
	closes++;
}

void astra_payload_test_completed(uint64_t target, uint64_t cancel, int target_result, int cancel_result, int cancel_seen) {
	assert(target && cancel == target + 1 && target_result >= -4095);
	assert(!cancel_seen || cancel_result == 0 || cancel_result == -2 || cancel_result == -114);
	completions++;
	printf("observed target=%llu result=%d cancel=%llu result=%d cancel_seen=%d\n",
	       (unsigned long long)target, target_result, (unsigned long long)cancel, cancel_result, cancel_seen);
}

void payload_scan_observed(int bytes, int checksum) {
	scans++;
	scan_bytes = bytes;
	scan_checksum = checksum;
	assert(scans == 1 && bytes >= 0);
}

static void receipt(void) {
	printf("payload-receipt submitted=%u closed=%u scans=%u bytes=%d checksum=%d\n",
	       submissions, closes, scans, scan_bytes, scan_checksum);
	assert(completions == submissions);
}

__attribute__((constructor)) static void setup(void) {
	assert(atexit(receipt) == 0);
}
