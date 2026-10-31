# ADR 0161: Finite checked PC device operations

The approved target is the [emulated PC profile](0159-selected-no-os-pc-target.md).
Source selects a closed operation with `[CCode(device="...")]` on an exact
`extern(C)` scalar declaration. This reuses the existing declaration/ABI path;
the compiler supplies its entire LLVM body. There is no C device provider,
arbitrary address, raw-pointer conversion or source assembly contract.

The [public declarations](../../lib/astra/platform/pc-devices.astra) use the
existing exact `int`/I32 ABI. Register values are 32-bit machine words; EDU
inversion is compared as a signed bit representation. UART admission restricts
the value to 0–255 before truncation and waits for the modeled transmitter.
Unsupported widths, parameters, orderings, foreign transport metadata or
hosted targets fail before emission. This adds no general C U32 channel.

EDU is the installed QEMU model `1234:11e8`, bus 0 slot 4, with memory decoding
enabled and BAR0 explicitly set to `0xf0000000`. Only the naturally aligned
32-bit liveness register at offset 4 is exposed; write followed by read produces
the bitwise inverse. The issued LLVM load/store is volatile and its exact
address, width, alignment, operands and source order are independently retained.
The [QEMU EDU specification](https://www.qemu.org/docs/master/specs/edu.html)
describes that register; actual qualification uses installed QEMU 10.2.2.
No DMA or interrupt-controller support is inferred.

The atomic domain is one compiler-owned, naturally aligned I32 RAM word,
distinct from MMIO. Load supports relaxed/acquire/sequence-consistent, store
supports relaxed/release/sequence-consistent, and fetch-add supports
relaxed/acquire-release/sequence-consistent. Fetch-add returns the old word and
uses explicit modulo-2^32 arithmetic; this does not change ordinary checked
integer arithmetic. The LLVM atomic instruction/order/alignment/address/input
are verified, and selected machine instructions and all admitted orders are
executed. These operations do not introduce thread migration, shared-object
atomic refcounts, Send/Sync promises or a general threaded language profile.

The breakpoint operation emits a real `int3` with a scalar register input and
result plus memory/flags clobbers. The startup vector saves registers and
x87/SSE state, invokes the exact source handler, and returns with `iretq`.
Source handler shape, absence of calls/external effects and target identity
are checked. Calling an ordinary annotated function is not counted as a trap.

The admitted operation is immutable source intent, separate from mutable stage
state. Checked-to-Core admission and independent Core/CFG/SSA/C ABI verifiers
reject a changed operation or signature. Metadata copies preserve the admitted
snapshot without retaining an upstream model. Physical LLVM witnesses retain
the body sequence, volatile operands and atomic order/alignment. The optimizer
cannot infer memory purity from these declaration policies.

Component qualification: A99 and A100 execute at O0/O1/O2 with independent
`EDU:OK` and `TRAP:41` serial traces. Missing EDU is refused. Invalid byte
admission and checked division by zero reach `PANIC:06` and failure exit 253.
Seven detached authority/target mutation and restore tests pass, alongside
selected inherited hosted volatile and runtime-free target regressions. Raw
receipts and corrected exploratory failures are external under the current
campaign runtime/build directories. This is component evidence; F3–F9 and the
complete Surge 12 corpus remain subject to final integrated qualification.
