// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <stdint.h>

// Observation only. Astra performs classification, indexing, cache operations,
// callback decisions and output. These counters observe producer resume sites.
static int32_t starts;
static int32_t resumes;
static int32_t created;
static int32_t retired;

int32_t astra_index_async_observe(int32_t operation) {
	switch (operation) {
	case 0:
		starts = 0;
		resumes = 0;
		return 0;
	case 1:
		starts++;
		return starts;
	case 2:
		resumes++;
		return resumes;
	case 3:
		return starts;
	case 4:
		return resumes;
	case 5:
		created++;
		return created;
	case 6:
		retired++;
		return retired;
	case 7:
		return created - retired;
	case 8:
		return created;
	case 9:
		return retired;
	default:
		return -1;
	}
}
