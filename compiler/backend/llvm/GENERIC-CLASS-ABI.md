# Bounded private generic Class storage

GENCLASS-16 extends the explicitly selected `class_storage` profile on GNU/Linux
x86-64 LP64 with LLVM 23.1.4. Qualification receipts and remaining gates belong
to the milestone report. This note describes the implemented contract, without
claiming whole-compiler admission or a public Class ABI.

A closed specialization retains its original nominal declaration, exact type
arguments and ownership flags. Binder node/symbol/reference maps preserve source
tokens and spans. The storage backend key also encodes exact declaration content,
target triple and data layout. Content encoding is lossless; its symbol-size cost
is included in the measured products. Equal physical shapes do not identify
different nominal records or different Class instances.

Private LLVM identifiers have a 65,536-byte adapter bound. Filesystem paths keep
their existing 4,096-byte bound, and the LLVM module retains its existing output
and work limits. An oversized generated callable name is refused before linkage
is applied. This changes no public C signature or source-language policy.

The eligible generic source has one type parameter, one to eight owned owner-slot
fields of that parameter, optional scalar fields, one bounded constructor and
nonvirtual nonthrowing methods. The inherited `ExactHeapClass` constraint remains
checked when present. Unconstrained declarations such as the unchanged library
`Vector<T>` do not acquire an invented constraint. Concrete elements must be
qualified exact Classes or plain copyable records. Owning records, generic-Class
elements, Resources, shared/weak policies and arbitrary destructor/allocator
contracts remain outside this storage policy. C0 rejects `Vector<int>` because
`int[slots]` is an invalid ordinary array extent; scalar-slot semantics are not
introduced here.

The Class handle is eight bytes. Its separately allocated payload contains the
actual source-ordered fields. An owner-slot descriptor is 16 bytes, aligned to
eight: backing pointer at zero, signed 32-bit count at eight, capacity at twelve.
Mutations retain the field address through Core, CFG, SSA and LLVM. They never
mutate a detached descriptor copy. Class elements use eight-byte handles and
exact per-element retirement. Record slots use the concrete record type, stride
and alignment, value transport and no invented per-element destructor.

Allocation and constructor invocation are separate. A constructor receives
exactly one hidden borrowed receiver followed by its source parameters. Retained
constructor templates have specialized parameter facts but do not acquire a
second executable receiver. The independent constructor consumer requires a
complete once-only initialization prefix before a bounded scalar/reserve tail.
Conditional initialization, receiver escape during initialization, arbitrary
partial-construction rollback and preinitialization local-owner staging remain
deferred. Normal methods borrow the live receiver; incomplete constructor fields
use the separate initialization inventory until publication.

Reserve checks descriptor consistency, requested extent and the actual target
stride, allocates before committing, transfers live entries and retires the old
backing. The default allocator follows C0's fatal exhaustion policy. Fatal traps
do not imply unwinding. Take shifts entries and clears the tail; replacement
retires an overwritten Class owner once, while copyable records remain values.
Moved state remains separate from an owned null handle. Source argument order,
loans and owner transfers are checked before physical lowering.

Source/type, constructor/field inventory, Core, CFG, SSA, native ABI and LLVM graph
consumers remain separate. The generic Class test consumer reconstructs original
field/type-parameter and callable channels independently of the storage planner.
New physical mutants are resealed and must pass LLVM's verifier before the
source/ABI correspondence consumer rejects them. Module/context-owned type and
layout caches retain their previous lifetime checks. Public scalar C boundaries
and the Vala compiler's source semantics are unchanged.
