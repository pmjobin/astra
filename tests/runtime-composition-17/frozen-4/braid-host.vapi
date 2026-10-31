// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
void braid_event(int kind, int identity, int value);
[CCode(cname="braid_custom_allocator")]
owned ConcurrentAllocator braid_allocator(i64 capacity, int slots, int identity);
