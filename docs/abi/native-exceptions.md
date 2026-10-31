# Native exception ABI plan (ERROR-1)

Source direction is E3-NATIVE-EXCEPTIONS-MESSAGE, from the approved work order.
ERROR-1-R1 records the implemented native-exceptions-v14 channels below.
Qualification is recorded separately in the current report.

The old nonpolymorphic lexical `C.init` and exact caller-result layouts remain
unchanged. Participating single-inheritance classes have one zero-offset base
prefix. Their header contains two target pointers: an immutable class descriptor
and an immutable original throw-site record (null before first throw). The
zero-offset base prefix is a nested target-layout aggregate, preserving the
complete base size, alignment and tail padding. Derived declared fields follow
in declaration order with target-native alignment. The descriptor contains the exact parent descriptor, a dynamic destroy
entry, and the virtual slot table. Descriptors are compilation-owned constants,
not name-based identifiers or a registry. Construction sets the most-derived
header, invokes explicit base initialization once, then initializes derived
fields. Virtual dispatch during construction or destruction is rejected.

`new C(args)` owns one stable heap allocation and calls the ordinary initializer.
Legacy lexical storage cannot become an escaping heap owner. Unique ownership
moves without copying the object. Dynamic destroy invokes derived deinit and
field cleanup, then base deinit and field cleanup, finally one deallocation.
The allocation entry preserves the existing fatal OOM boundary. Snapshot string
fields contain `{ptr, i32}` and own exactly the counted immutable UTF-8 bytes;
empty snapshots contain a null pointer and zero count. Creation copies input
before its borrow ends. Reading a snapshot or a proved message getter performs
no allocation, release, mutation or I/O.

A native throwing entry returns one nullable unique exception pointer. Its
physical arguments preserve the existing leading sum-result storage pointer,
then the receiver where present. For other nonvoid checked results, the private
success-storage pointer follows the receiver and precedes explicit argument
groups. A free function has no receiver. A checked sum uses its leading sum
slot as success storage and adds no second slot. Void has no success slot.
Null means success storage is fully initialized; nonnull means success storage
is unavailable. Result storage has the existing result's exact physical shape:
scalar/vector, record, sum, buffer pair or heap-owner pointer. No source Result,
Outcome, capture, global pending state or C unwind participates. Expected private
profile is native-exceptions-v14, after owned-sums-v13; prior profiles stay fixed.

The same new profile first carries receiver-bounded immutable text getter
results. Their physical result is the existing `{ptr, i32}` carrier, with an
explicit `receiver-text` lifetime contract and exact class/property receiver
identity. Nonthrowing entries keep their existing channels. A profile number
does not imply that the exception channel or the complete campaign is delivered.

Each protected group has ordered exact class bounds and separate generated
handler/propagation edges. Catch borrows the owned dynamic object. Bare rethrow
transfers the nearest lexical catch owner, retaining the original header and
origin record. Replacement evaluates and snapshots incoming text before old
catch cleanup. Escaping effects use declared open subtype bounds. A narrower
catch cannot exhaust a declared ancestor bound by enumerating visible leaves.

The root nomination resolves one exact ordinary class and its get-only virtual
string `message` slot. That slot has a receiver-bounded result contract even for
literal overrides. The permitted diagnostic getter subset is literal/constant
or initialized readonly snapshot reads and validated base access; helpers and
unproved effects reject. Ordinary unrelated computed properties keep their
existing effectful behavior.

Retained authorities must distinguish exact parent/field/slot/receiver identity,
heap versus lexical origin, success versus exception disposition, catch owner,
original origin, reservation consumer and crossed loan extent. Local validity,
source correspondence and LLVM binding checks are separate gates; equal pointer
widths or balanced cleanup counts cannot substitute for any of these gates.

Compatibility: `throws`, `throw`, `try`, `catch` are newly reserved. `new` remains
contextual and additionally accepts `new C(args)`. `virtual`, `override`,
`readonly`, `base` are contextual class additions. `message`, `what`, `Error`,
`RuntimeError` and `ExceptionRoot` are not globally reserved. No literal, escape,
interpolation, formatting or output API changes are authorized.

Virtual call refinement recorded before its lowering: each logical slot has
an ordinary implementation pointer followed by a pointer for the inherited
private checked channel. A nonthrowing override of a throwing slot uses a
compiler-generated fastcc adapter in the second entry. The adapter forwards
its receiver and ordinary argument groups, writes the complete successful
value to inherited success storage, and returns null. A throwing override
uses its native private entry, whose physical shape agrees with the inherited
slot while its declared source bound can narrow. Calls select the channel
specified by their static member declaration. Subclasses cannot broaden an
override's checked bound. Ordinary nonthrowing slots use their existing ABI.

ERROR-1-R1 distinguishes heap-origin factories and owned Class parameters from
the old caller-backed Class result/parameter contracts. The global source
program resolves one allocation domain for each ownership signature before
checking bodies. Heap results return one owned PTR; checked heap results publish
that PTR through their exact success slot. Their NativeObjectOriginPlan copies
the declared class identity and heap domain. Forwarding preserves the original
pointer, including a derived-to-base heap upcast, without candidate storage or
object slicing. Null is an initialized empty owner; a null throw uses the fatal
invalid-use guard. Mixed heap/caller-backed ownership signatures reject.

Stored receiver views add compile-time owner, loan and lexical-extent authority.
Copies do not allocate or retain the receiver. Every possible backing owner of
a merge must outlive the destination; receiver invalidation rejects while a
loan survives. Exception edges preserve the appropriate view versions, and
exited extents end before backing cleanup. Return expressions are captured
before their loans end. These markers have no LLVM runtime representation.

The qualified GNU LP64 calloc path admits the current naturally aligned class
fields (scalars, at most 128-bit vectors and existing aggregates) only with an
independently retained complete target size/alignment witness. Alignment is at
most 16 bytes; calloc supplies fundamental alignment. This is a checked target
premise, not a promise for future over-aligned fields or another allocator.
