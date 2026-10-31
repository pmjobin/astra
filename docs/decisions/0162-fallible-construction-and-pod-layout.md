# ADR 0162: Explicit nullable construction and natural C POD storage

Status: implementation decision for Surge 12; final qualification pending.

`try_new Class(scalar_arguments)` uses the exact Class declaration's checked
allocation policy. It returns an ordinary nullable unique owner on exhausted
admission. The allocator validates the complete extent, alignment, origin and
budget before publication. A null result skips hidden initialization and the
constructor; ordinary owner cleanup then skips the null reference. Constructor
arguments retain their ordinary evaluation order. Initially they must be
unmanaged integer, floating or bool scalars, and the construction site must be
synchronous. Owned/borrowed inputs and uncertain async admission reject.
Ordinary `new` retains its fatal failure behavior, including for an explicit
policy. No default constructor, ownership or public pointer ABI changes.

Checked storage carries a distinct immutable fallible-admission flag through
Core, CFG and SSA. Every stage checks that this refers to fresh heap storage,
an explicit policy and its exact scalar constructor. Nonnull analyses rebuild
their facts without assuming successful `try_new`. Native ABI plans retain
independent admitted storage/Class/constructor identities; LLVM verifies the
exact admission calls and complete initialization/constructor control flow.
Policy Class allocations are excluded from automatic stack promotion.

`[Repr(layout="C")]` selects a declaration-order natural LP64 scalar POD record.
The finite initial family has 1..32 integer/f32/f64 fields, without bool,
pointers, ownership, nested records, methods or hidden state. An optional
`[Align(bytes="N")]` requests a power-of-two minimum no greater than the
record's natural C alignment. Greater record alignment rejects rather than
silently changing stride, C by-value classification or nested layout. Exact
Class allocation alignment is separate and supports powers of two up to 4096.

Each stage owns an admitted POD field-name/type/order/alignment snapshot.
The native plan retains that primitive layout without an upstream graph;
LLVM independently compares actual field types, offsets, complete size and
alignment. Existing finite `natural-lp64` C import/export rules still apply.
The selected layout is qualified only for GNU x86-64 LP64 and the approved
x86-64 no-OS PC profile. It makes no native Class C-representation claim.

Native module interfaces serialize the storage attributes before their type
declarations, preserving policy identity under the existing interface hashes.
Named domains coalesce only with the same complete storage policy. Custom
placement callbacks remain in one checked compilation unit; a cross-module
custom policy rejects until its callback-code lifetime has a separate proof.
