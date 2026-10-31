// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
void query_event(int kind, int identity, int value);
[CCode(cname = "query_custom_allocator")]
owned ConcurrentAllocator query_allocator(i64 capacity, int slots, int identity);
