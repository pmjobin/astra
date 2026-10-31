// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
void sequence_event(int kind, int identity, int value);
[CCode(cname = "sequence_custom_allocator")]
owned ConcurrentAllocator sequence_allocator(i64 capacity, int slots, int identity);
