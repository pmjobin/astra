# Exact field Place projections

STRUCT-1 separates authoritative aggregate storage from computed aggregate
values. Only the former exists. For `Pair p`, the ordinary LocalSymbol carries
the canonical StructType; its CoreLocalPlace and CfgLocalPlace are authoritative
aggregate bases. `p.x` projects that exact base through an exact field descriptor:

```text
StructSymbol → CoreStruct → CfgStruct
StructFieldSymbol → CoreStructField → CfgStructField
LocalSymbol : StructType → CoreLocalPlace → CfgLocalPlace
(Place, field) → CoreFieldPlace → CfgFieldPlace
leaf Load / Initialize / Store → ordinary SSA promotion → scalar/vector values
```

A field's identity is its object, not its spelling, declaration ordinal, source
position, or physical byte offset. A projection's authority includes both its
exact aggregate base and exact declared field. `a.x` and `b.x` have different
projection objects even when their field descriptor is shared. Repeated `a.x`
reads and writes reuse one canonical projection object per stage. Detached scalar
copies cannot replace this authority.

`StructType` is a safe shared nominal type object containing only a display name.
It never points back to semantic symbols. CheckedProgram owns StructSymbols;
each owns its type and ordered fields. CoreProgram and CfgProgram instead own
stage-specific descriptors and fields. Field-to-containing-struct links are
expiring WeakRefs. Functions own their aggregate bases and `field_places` arrays;
projections strongly retain bases and fields. Bases own no projections. Thus
retaining a projection may retain its base, but cannot form a cycle or keep a
function/program alive. A detached field's containing descriptor may expire.

Builders use temporary exact identity maps for semantic field → Core field,
local → Core base, `(Core base, Core field)` → canonical Core projection, Core
base → CFG base, Core field → CFG field, and Core projection → CFG projection.
Names are consulted only during semantic binding. Semantic destruction cannot
invalidate Core; Core destruction cannot invalidate CFG. No syntax tree survives
as field/type authority. Declaration, name, initializer, and access spans retain
source provenance independently.

CheckedStructLocalDeclaration owns its ordinary LocalSymbol and an array of
CheckedFieldInitializers in written source order. Each holds the exact field,
checked leaf expression or recursive CheckedStructInitializer, and initializer
span. CheckedFieldPlace binds an exact Place base and field object. Historical
direct leaf references/assignments remain compatible, with exact types and
access/assignment provenance.

Core retains nested braces in CoreStructInitialize statements targeting exact
subobjects, with ordinary leaf CoreInitialize statements in written order.
It creates no aggregate Value or temporary. The complete sequence establishes
initialized aggregate storage. CoreLoadValue reads a leaf CoreFieldPlace;
CoreStore replaces that leaf after computing the RHS. CFG uses the corresponding
CfgInitialize, CfgLoadValue, and CfgStore. Existing expression lowering preserves
calls, evaluation instructions, short-circuit joins, and trap order; a field's
Initialize follows its complete expression join.

Both verifiers validate program-owned struct/type authority, acyclic by-value
struct graphs, permitted field types, exact ownership and ordinals, unique names, and function-owned
canonical projections. The complete projection array must follow containing
local ordinal then recursive declaration preorder, with no missing, duplicate,
foreign, scalar-base, or mismatched projection. Type checks reject aggregate
values and direct aggregate base Initialize/Load/Store. Each field must have
exactly one initialization; later leaf Stores are allowed. Core additionally checks
one contiguous declaration sequence in a structured block and forbids partial
local availability. CFG counts initialization across preserved reachable and
unreachable blocks; it does not infer definite assignment from block order.

Dumps expose authority without physical layout:

```text
(struct-local-place #0 "p" : Pair)
(field-place (base struct-local-place #0 : Pair) (field #0 "x") : int)
(load : int
	(field-place (base struct-local-place #0 : Pair) (field #0 "x") : int)
)
```

SSA promotion includes scalar/vector source locals, leaf projections whose root
local is not address-taken, and compiler temporaries. Struct bases are excluded. Ordering is locals by
local ordinal, then fields by local/recursive field order, then temporaries. The existing
iterated-frontier placement and dominator-stack renaming algorithm runs unchanged
on exact CfgPlace identity. Initialization-dominated availability handles body-local
fields without fictitious outer-header definitions or undef/poison.

For a non-address-taken p, a branch mutating only `p.x` creates one scalar join parameter; unchanged `p.y`
keeps its definition. Mutating both creates two independent parameters. Loops
carry only the required scalar Places, using ordinary block/edge arguments.
SsaBlockParameter adds only copied debug provenance: FIELD kind, local ordinal,
field-ordinal path, display name such as `p.x`, and spans. No descriptor, StructType, or Place for a fully
scalarized struct survives in SSA unless separately needed for typed pointers or
addressable storage. No aggregate value or aggregate register is introduced.

These non-address-taken fields are independently promotable because no
language operation aliases their storage. Unions, overlapping fields, and
whole-struct operations remain unsupported. A `void*` field holds a foreign address value, not the address of itself
or its aggregate base. Scalarization does not define native layout, ownership,
or struct ABI. For non-addressable fields LLVM sees ordinary scalar SSA and
needs no struct type, aggregate extractvalue/insertvalue, alloca, or offsets. Native and C
physical channels/profiles are unchanged.

## Direct and indirect aliases

TPTR-1 adds CoreIndirectFieldPlace/CfgIndirectFieldPlace with an exact typed
pointer value and exact field descriptor. AddressOf references the exact
address-taken aggregate local. A direct p.x and indirect q->x can therefore reach
the same storage. Neither direct address-taken fields nor indirect fields may
promote independently; all fields of the borrowed local stay in memory for the
whole function. Other struct locals continue to scalarize.

SSA owns layout-free struct descriptors, addressable storage, and separate
direct/indirect field memory Places. Ordered Initialize/Load/Store preserve
writes visible through aliases, including native calls. No source field lookup,
physical offset, whole-struct value, or aggregate copy appears. See
[addressable storage](addressable-storage.md) for the precise promotion barrier
and stage lifetime contract.

## Recursive struct fields

STRUCT-AGG-1 extends the direct-local model above to [recursive field Places](recursive-field-places.md).
Exact base/field identities compose over Places, nested scalar/vector leaves retain
promotion eligibility, and addressed roots lower recursively. Struct subobjects are
Places without whole-aggregate Values. Nested initialization is direct storage;
no copy, aggregate ABI or class aggregate support is implied.
