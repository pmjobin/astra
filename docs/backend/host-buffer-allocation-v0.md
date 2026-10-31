# Hosted buffer allocation v0

BUFFER-1 qualifies one physical strategy: the system C allocation environment
on x86-64 Linux GNU LP64. The compiler adds no dependency or mandatory Astra runtime
library. Buffer-free programs gain no allocator declarations or emitted symbols.

`new T[count]` is a native semantic allocation operation. Core/CFG do not define
it as a C call. `LlvmBufferAllocation` realizes the checked operation after
element layout and ownership groups are fixed. The target-machine configuration
gate rejects unqualified allocator targets before object emission with:

```text
error: owned runtime-array allocator is not qualified for target '…' (requires hosted x86-64 Linux GNU LP64)
```

The existing driver remains host-target based. Standalone qualification probes
the same gate with Linux GNU LP64 x86-64 and representative AArch64, Windows,
freestanding, GNU x32 and unqualified musl triples. GNU x32 has 32-bit pointers
and size_t despite naming the x86_64 architecture; it cannot use this I64 size_t
realization. There is no new cross-target source or CLI policy. Other hosted C
environments require separate qualification before extending this gate.

## Physical lowering

1. Compare the I32 count with signed zero; negative values trap.
2. Branch on zero. Empty bypasses allocation and yields null base, I32 zero.
3. Extend the nonnegative count to backend I64 size_t. Obtain the exact LLVM
   element storage size and use `llvm.umul.with.overflow.i64` before allocation.
4. Trap on overflow. Otherwise call direct C `calloc(count, element_size)`.
5. Trap on null for nonempty allocation, or enter an explicitly selected
   [fatal action region](../ir/allocation-failure.md) and trap if its call returns.
   Publish the complete PTR/I32 owner only
   on successful return. Zero initialization covers the entire element storage.
6. Deallocate through direct `free(base)`, guarded against null. Empty cleanup
   performs no host call. Source state and cleanup strategy are not runtime data.

Integer/bool zero bits, IEEE binary32/binary64 positive-zero bits, null opaque
pointers, zero numeric lanes and false mask lanes all agree with zero-filled
storage on this qualified backend. There is no hidden uninitialized fast path.

The largest admitted element occupies 16 bytes. The hosted allocator guarantees
alignment suitable for these x86-64 Linux scalar/vector loads. LLVM uses ordinary
element ABI alignment, never a stronger vector alignment. Tests assert 16-byte
alignment of every observed allocation and exercise all lanes of small and
largest admitted vectors, floating vectors and masks. Mask memory uses its exact
LLVM vector storage size, including the 2-byte `<16 x i1>` shape.

LLVM's builtin allocation optimization can remove allocation/failure paths when
it proves element contents irrelevant. OOM is observable in Astra, so both
allocator declarations and direct call sites carry `nobuiltin`. This retains
the call/trap behavior at O2 without runtime indirection or disabling ordinary
numeric optimization. Floating contraction/FMA policy is unchanged.

I32 maximum count times the largest current element is only 34,359,738,352 bytes,
so size_t overflow is unreachable for valid BUFFER-1 elements on this host.
An independent physical-stage test uses a deliberately enormous LLVM layout to
execute the same checked-multiply overflow path at O0/O2/FMA, trapping before any
allocator call. That layout is never admitted as an Astra buffer element.

The test companion injects deterministic failure using link-time
`--wrap=calloc,--wrap=free`, records exact allocation/free identity and detects
double cleanup. These wrappers are test-only; production calls remain direct.

Bounds validation reuses existing Slice lowering. Checked indices reach element
GEP and load/store only after the trap branch. Ownership transport uses pair
loads/stores and LLVM-only result carriers; no element-copy loop, memcpy or
memmove is generated. Resource and buffer cleanup ordering is already concrete
when this backend runs; it performs no semantic lifetime analysis.

Custom allocators, arenas and freestanding heaps require a future qualified
static realization. The semantic operation and cleanup authority are the
extension point. No global heap requirement is imposed on buffer-free programs.

Generic new T[count] reaches this authority only after exact element substitution and concrete verification. It retains target stride/alignment, checked physical arithmetic, zero initialization, fatal OOM and qualified allocator effects including nobuiltin. The generic frontend introduces no allocator/provider interface.
