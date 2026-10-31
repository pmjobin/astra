# Internal continuation physical boundary

The [logical contract](../ir/internal-continuations.md) and
[ADR 0086](../decisions/0086-internal-continuations.md) govern this compiler-only
boundary. Existing NativeAbiVersion and CAbiProfile values and domains are unchanged.

On qualified GNU LP64 x86-64 Linux, the descriptor contains four pointers: step
at offset 0, cancel-drain at 8, destroy at 16 and environment at 24. Extent is 32
bytes; alignment is 8. Runtime selection chooses between two exact compatible
generated steps. The logical association survives independent plan verification
and code/environment correspondence before physical expansion. Names supply no
missing code identity.

Step/cancel-drain wrappers use internal fastcc `I32(PTR environment, I32 argument)`;
destroy uses internal fastcc `void(PTR environment)`. The exact first state leaf
is an int and supplies the invocation result. Matching physical signatures do
not authorize interchangeable operation roles. Environment-free entries call
their exact `I32(I32)` bodies without captures, use null environment/destroy slots,
and emit no allocation or destructor call.

Environments hold an int or an existing concrete copyable record with leading int,
and optionally an existing concrete owned int buffer. Storage follows recursive
declared fields and existing natural layout/stride/alignment authority, never
flattened register results. Target configuration compares LLVM sizes, offsets and
alignments with independent plans. Allocation and destruction reuse qualified
calloc/free lowering with overflow/null guards and fatal failure behavior. The
witness's nested state/environment extents are 24/40 bytes, its three-int buffer
is 12 bytes, and the scalar environment is 4 bytes.

Invocation loads selected code and exact environment from one descriptor, emits
an indirect call, snapshots every state leaf into existing native value channels,
calls the exact SSA body and stores the whole result. Buffer pointer/count channels
are a bounded synchronous view while the unique owner remains in the environment.
Record transport preserves F32/F64 and whole-vector leaves without arithmetic
changes or pointer-based record aliasing.

Unoptimized costs are a 32-byte local descriptor, code/environment loads, indirect
wrapper dispatch, state snapshot/result loads/stores and a body call. This first
move adds a destination carrier and zeroes the source. Each stable environment
has one allocation plus an optional separate buffer allocation and ordered cleanup.
Invocation/retention witnesses have zero runtime counter/library cost. O2 may
devirtualize calls or remove carriers; preserved-call controls inspect indirect
invocation separately without imposing an optimizer-specific instruction sequence.

Malformed associations, signatures, initialization and ownership/use schedules
reject at SSA or native-plan verification. Correspondence rejects valid substituted
plans. Physical verification checks emitted selection, publication, calls and moves.
These are internal verification errors, not new source diagnostics. Safe generated
construction requires no dynamic misuse checks. Foreign forged pointers, arbitrary
threads and provider quiescence remain outside this boundary.
