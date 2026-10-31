// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
[CCode(destroy_function = "astra_context17_destroy", context = "owned-concurrent")]
handle ConcurrentAllocator;
[CCode(destroy_function = "astra_context17_destroy", context = "owned-affine")]
handle AffineAllocator;
[CCode(destroy_function = "astra_context17_destroy", context = "owned-transfer")]
handle TransferAllocator;
[CCode(destroy_function = "astra_context17_destroy", context = "scoped-affine")]
handle ScopedAllocator;
[CCode(cname = "astra_context17_open_concurrent")]
owned ConcurrentAllocator concurrent_allocator(int kind, i64 capacity, int slots, int alignment);
[CCode(cname = "astra_context17_open_affine")]
owned AffineAllocator affine_allocator(int kind, i64 capacity, int slots, int alignment);
[CCode(cname = "astra_context17_open_transfer")]
owned TransferAllocator transferable_allocator(int kind, i64 capacity, int slots, int alignment);
[CCode(cname = "astra_context17_open_nested")]
owned ConcurrentAllocator nested_allocator(borrowed ConcurrentAllocator parent, int kind, i64 capacity, int slots, int alignment);
[CCode(cname = "astra_context17_query")]
i64 concurrent_allocator_query(borrowed ConcurrentAllocator context, int query);
[CCode(cname = "astra_context17_query_affine")]
i64 affine_allocator_query(borrowed AffineAllocator context, int query);
[CCode(cname = "astra_context17_query_scoped")]
i64 scoped_allocator_query(borrowed ScopedAllocator context, int query);
