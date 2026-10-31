// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(cname = "m17_custom_allocator")]
owned ConcurrentAllocator custom_allocator(i64 capacity, int slots);
