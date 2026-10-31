// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
void range_event(int kind, int identity, int value);
[CCode(cname = "range_custom_allocator")]
owned ConcurrentAllocator range_allocator(i64 capacity, int slots, int identity);
