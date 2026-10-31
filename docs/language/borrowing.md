# Borrowing typed data

Borrowed `string[]` views cover both table and payload lifetimes. Per-write origins preserve saved list/element copies across rebinding, and extracted strings cannot escape through STATIC_TEXT results. All permitted text-slice producers are borrowed parameters; local descriptors do not own backing storage. See [text-slice IR](../ir/text-slices.md).

[Computed properties](properties.md) can be accessed through `borrowed ClassType`
parameters using the existing temporary receiver borrow and nullable reference
check. Two borrowed references may alias: a setter through one and getter through
the other must observe coherent storage, including at O2. Accessors introduce no
noalias contract. Borrowed property values and handle-valued properties are
deferred to a later ownership/borrowing property milestone.

Object lifecycle remains attached to the backing storage, so existing
LexicalRegion proofs also prevent a reference from surviving destructor execution.
Aliases create no cleanup, and an inner alias does not end an outer object's
lifetime. Constructor `this` is an INITIALIZING receiver that cannot escape or be
converted into an ordinary ClassType reference; deinit receives LIVE storage.
Explicit borrowed Resource/slice/ClassType constructor parameters retain native noescape
contracts. See [object lifecycle](object-lifecycle.md).

## Object references in OBJ-1

ClassType references reuse LexicalRegion and BorrowProvenance. Construction
borrows its separate object's storage region; null has no live-storage requirement.
Copy and rebinding use the existing conservative stored-borrow rule: a reference
local read summarizes at that local's region. Same-region and ancestor-to-descendant
copies are valid; a descendant reference cannot be stored in an ancestor binding.
This includes conservative rejection of an inner alias copied back outward, even
if it originally came from an outer object. No flow-sensitive provenance sets or
exclusivity are introduced. Reference rebinding leaves the construction's storage
alive until its own scope ends. Native plain `C` and explicit `borrowed C` parameters use the same
BORROWED_NOESCAPE contract as slices and handles, with function-region authority.
They are nullable, mutable and aliasable; local copies and forwarding preserve
exact ClassType and cannot escape that region. Null has no ObjectStorage provenance.
No cleanup responsibility crosses the call, and no runtime borrow token exists.
Unqualified/borrowed object results remain unsupported; explicit owned parameters/results retain their distinct transfer contracts. Methods and
lifecycle callables use distinct compiler-owned nonnull receivers. See
[borrowed object parameters](borrowed-object-parameters.md). See [objects](objects.md) and [storage IR](../ir/object-storage.md).

[Struct method receivers](methods.md) are a separate compiler-owned non-owning
contract. A direct-local method call borrows exact mutable instance storage for
the invocation; `this.method()` forwards the same receiver. The receiver is
nonnull by construction and cannot escape, be rebound, copied into a pointer,
moved or released. It is not a source `borrowed S*` parameter. Existing lexical
Struct* aliases may coexist and observe method mutations; no exclusivity or
noalias promise follows. Explicit method `borrowed Resource` and `borrowed T[]`
parameters retain the ordinary native borrowing rules described here and in
[slices](slices.md).

[Slices](slices.md) reuse these same lexical regions. `slice(a)` and
`slice(a,start,count)` borrow a direct array local's region. Slice storage must
not outlive that region; same-region and outer-array-to-inner-slice uses succeed,
while inner-array-to-outer-slice rebinding rejects. Copies preserve borrowed
storage; reads conservatively advertise the slice local's own region after the
stored-borrow proof. Mutable aliases and overlapping subranges are permitted.
Empty views retain provenance, and slice values carry no ownership or cleanup.
Bare `{ ... }` blocks create the same scoped regions as if/while bodies.

For [numeric vectors](vector-memory.md), `&v` carries v's existing lexical region.
Stored same-region and ancestor-region borrows and call-bound `mutate(&v)` work.
`mutate_two(&v,&v)` is permitted: lifetime proofs impose no mutable exclusivity.
An inner vector pointer cannot escape into an outer pointer local, and native
vector-pointer parameters guarantee the function region. Addressability changes
storage promotion, independently of Resource ownership and cleanup.

[Lexically stored borrows](borrows.md) govern all typed data pointers, including
supported integer/f32 pointers, numeric VectorType pointers, and existing Struct*. Address-of ties a pointer
to its direct local's region; pointer storage must not outlive that region.
Native parameters guarantee their invocation, and null needs no pointee lifetime.

These proofs permit multiple mutable aliases. They imply neither ownership,
readonly access, nor exclusivity. The [typed pointer guide](typed-data-pointers.md)
shows stored, call-bound, and rejected escaping borrows; the canonical
[borrow guide](borrows.md) explains conservative pointer-local provenance.
