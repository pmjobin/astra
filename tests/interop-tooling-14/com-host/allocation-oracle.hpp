// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// One test translation unit only. Tracks the selected generated wrappers and
// injects nothrow allocation failure without altering Windows or its allocator.
#include <new>
#include <cstdlib>
static unsigned allocation_fail_after;
static unsigned allocation_live;
static unsigned allocation_total;
static unsigned allocation_retired;
static void *allocation_slots[512];
void *operator new(size_t bytes, const std::nothrow_t &) noexcept {
	if (allocation_fail_after && --allocation_fail_after == 0) return nullptr;
	void *result = std::malloc(bytes);
	if (!result) return nullptr;
	for (void *&slot : allocation_slots) {
		if (!slot) {
			slot = result;
			++allocation_live;
			++allocation_total;
			return result;
		}
	}
	std::abort();
}
void operator delete(void *value) noexcept {
	for (void *&slot : allocation_slots) {
		if (slot == value && value) {
			slot = nullptr;
			--allocation_live;
			++allocation_retired;
			break;
		}
	}
	std::free(value);
}
void operator delete(void *value, size_t) noexcept {
	::operator delete(value);
}
