# ADR 0077: Copyable struct collection elements

Status: accepted (ASTRA-STRUCT-ELEM-1).

Baseline: `2ddc218119198814afd27c25e6f22575bfb7a4ec`.

## Decision

Extend the existing exact `ArrayType(S,N)` and `SliceType(S)` identities to
nonempty concrete structs with complete, ordinary copyable, trivially destructible
storage and a defined structural zero. Eligibility recurses through declared
fields. It admits the existing bool, integer, f32/f64, unmanaged `void*` and 24
numeric/mask vector leaves. Concrete generic-origin records follow this same rule;
their definitions and arguments retain nominal identity.

Interning a collection identity is a shallow operation. Using that identity for
storage requires a stage-owned complete field graph. The shared copyability
authority remains distinct from zero and destruction predicates. Neither this
decision nor a raw pointer field proves any pointee lifetime.

Use one indexed Place root composed with recursive FieldPlaces. Capture the
collection and index once, guard before forming the element address, and reuse
the root for every leaf. Whole-record assignments validate the destination before
evaluating their producer, capture every source leaf, then write the destination.
Completed lifetime-neutral snapshots cease borrowing their original storage;
destinations and method receivers keep live addresses through the store or call.

Fixed local arrays accept complete positional entries, including existing bounded
struct producers and expected-type named field storage initializers. Initialization
finishes each entry before the next entry; the array name is unavailable until
all entries are initialized. Owned arrays retain BUFFER's one allocation and
PTR/count ownership group, structural zero, replacement order and non-unwinding
traps. There are no element constructors or destructors.

The memory layout is the ordinary addressable record layout, with declared field
order, nested offsets, padding and allocation stride. It is independent of
aggregate-v7's register channels. A new independent `struct-elements-v11` profile
describes exact recursive element shapes and slice borrow/owner transfer contracts.
It leaves older profiles unchanged. Physical qualification initially covers
x86-64 Linux; allocation additionally requires the existing hosted GNU LP64 gate.
Checked size and offset arithmetic uses the 64-bit physical address domain.

## Alternatives and boundaries

Boxing each element would change memory layout, allocation count and value-copy
semantics. Flattening memory into ABI channels would lose record padding and
alignment. Separate collection identities for owned/borrowed records would split
the existing lifetime contract from its canonical element identity. All three
alternatives are rejected.

Reusing bounded producers and scalar/vector snapshots preserves promotion of
ordinary unaddressed struct locals. A universal aggregate value/SSA representation,
aggregate phi, C record ABI, sret/byval transport, runtime type descriptor and
mandatory temporary record allocation are unnecessary and remain excluded.

This decision does not admit stored borrows, Resource/Class/text/slice/array fields
in elements, nontrivial element lifetime, generic `T[]` transport, generic Copy
capabilities, element address-taking, arbitrary temporary member receivers,
whole-array values, resizing, new allocation policy or new runtime dependencies.

See [language](../language/struct-elements.md), [IR](../ir/struct-elements.md),
[native profile](../abi/native-struct-elements-v11.md) and
qualification.
