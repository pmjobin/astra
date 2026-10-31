# Checked construction and incomplete native instances

An explicitly selected `declarations-v1` constructor may declare a checked throws
bound and the same exhaustive foreign error mapping used by methods. A failing
factory keeps its result empty, maps and retires the native exception, and retires
consumed inputs exactly once. Historical constructor admission rules outside this
profile retain their existing behavior.

Each admitted constructor records completed owned-field initialization in a bounded
stack of field ordinals. The limit is 4,096 owned fields per constructor. Failure
pops that stack in reverse actual acquisition order, independently of declaration
order. It never reads an uninitialized field or runs the user destructor on a
partially initialized instance. Typed cleanup covers Class owners, text snapshots,
owned buffers, owning records, slots, closures and native resources. Lazy cache
retirement is guarded by its initialized state. Existing rules still forbid calling
instance properties during initialization; this slice exercises empty caches on
failure and populated caches on successful full retirement.

Core retains the complete owned-field and lazy-cache inventory. CFG and SSA carry
an explicit constructor-abort operation immediately before each escaping exception
return. Independent verifiers reconstruct that inventory, its receiver and the
required error paths. The native plan binds exact Class/member and field ordinals;
LLVM verifies the complete acquisition/retirement sequence against that plan.
Detached mutations remove inventories, abort operations, native authority and a
same-typed acquisition ordinal. Restoring each mutation restores validity.

The callee cleans its completed field acquisitions. The caller retires raw heap
backing and monitor state after a constructor failure; lexical backing remains
lexical. Shared construction retains the existing heap-only rule. A completed root
whose foreign wrapper allocation fails follows ordinary full retirement, including
the user destructor. Wrapper retirement disables admission before destructor
reentry. The fault-injection checks target bridge allocation, rather than changing
the native allocator's contract.

Independent and generated-header C clients exercise failure before any transfer,
after each out-of-order transfer, after text and buffer initialization, and through
owning records, slots and lazy caches. They check retirement order and counts,
ordinary native heap and unique lexical callers, pre-transfer allocation refusal,
post-construction wrapper failure and reentry. The unique/shared O0/O1/O2 matrix
passed 52 commands and eight unsuppressed whole-executable Valgrind runs. This is
an intermediate M16 result; imports, callbacks, COM/GObject personalities, opaque
SDK composition and final qualification remain required.
