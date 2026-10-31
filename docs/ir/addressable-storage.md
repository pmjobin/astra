# Addressable storage and ordered SSA memory

Addressability is semantic storage authority. If a supported scalar or native
struct local is borrowed, direct accesses and indirect pointer accesses may alias
that same storage. A post-call direct read must observe callee mutations.

```text
LocalSymbol.address_taken
	→ CoreLocalPlace.address_taken
	→ CfgLocalPlace.address_taken
	→ SsaAddressableLocal
	→ backend-private alloca
```

Valid direct-local address expressions mark LocalSymbol, including stored borrows
and compatible native arguments. The
mark is conservative across the entire checked function, including preserved
unreachable code. Builders copy it through exact identity maps; SSA and LLVM
never rescan source text to infer addressability.

## Checked, Core, and CFG authority

CheckedAddressOfExpression owns the exact local, canonical TypedPointerType,
and source span. CheckedIndirectFieldReference and CheckedIndirectFieldAssignment
retain the checked pointer reference, exact StructFieldSymbol, and provenance;
the latter also owns its checked RHS. The pointer reference is a local or
parameter value; its TypedPointerType retains the exact pointee.
CheckedDereferencePlace retains an integer/f32 pointer expression and exact
pointee type; CheckedLoadExpression and CheckedStore use that Place.

CoreAddressOfValue and CfgAddressOfValue reference the exact addressable
scalar/aggregate local Place and retain its matching pointer type. CoreIndirectFieldPlace
and CfgIndirectFieldPlace contain a pointer value and exact stage-owned field.
CoreDereferencePlace and CfgDereferencePlace retain a pointer value, exact
directly dereferenceable pointee, provenance snapshot, and null-trap contract.
Existing direct FieldPlaces still project an aggregate local base. The classes
are distinct: a pointer value is not the storage of its pointee or of its own
local variable. Names, debug ordinals, and offsets never substitute for identity.

Indirect reads use ordinary LoadValue; indirect assignments use Store with the
checked RHS. Struct-field lowering preserves RHS-first assignment; scalar
dereference captures the pointer base first, then evaluates RHS and stores.
CFG captures
memory reads at their expression positions with CfgEvaluateInstruction.
Its ordered-evaluation checks also preserve earlier trap-capable computations
before a later memory read, and earlier reads before a later mutating call.
Address values occupy their argument position. No new CFG successor model is
needed; source control flow, short circuit, dominance, and loop targets remain
unchanged.

Core/CFG verifiers enforce canonical supported pointer types, exact
program-owned struct/field descriptors, exact direct/indirect projections,
addressable scalar/aggregate address targets, and matching load/store/address types.
Indirect Initialize and whole aggregate Load/Store are invalid. Core additionally
requires the complete field initialization sequence before borrowing a local.

| Place | Promotion eligibility |
| --- | --- |
| Non-address-taken scalar source local, including T* local | Eligible |
| Address-taken scalar source local | Ineligible |
| Compiler temporary | Eligible |
| Direct field of a non-address-taken aggregate | Eligible |
| Aggregate local base | Ineligible |
| Direct field of an address-taken aggregate | Ineligible |
| Indirect field | Ineligible |
| Dereference | Ineligible |
| Vector lane extraction | Not a Place |

Eligibility is per storage object. A function containing an addressable b and
an untouched a still promotes a's fields independently. All fields of b remain
memory-backed even if a particular callee appears to touch only x.

## SSA-owned memory model

| Representation | Authority |
| --- | --- |
| SsaStruct / SsaStructField | Exact nominal type, ordered scalar fields, copied names/spans; no layout |
| SsaAddressableLocal | One local storage object, exact scalar type or SsaStruct, dense storage ordinal, copied local provenance |
| SsaLocalMemoryPlace | Exact addressable scalar storage |
| SsaDereferencePlace | Typed pointer SsaValue, exact scalar pointee, lexical provenance snapshot, null-trap contract |
| SsaDirectFieldPlace | Exact addressable storage plus exact field |
| SsaIndirectFieldPlace | Typed pointer SsaValue plus exact field |
| SsaAddressOfInstruction | Exact storage target and one ordinary T* SSA result |
| SsaInitializeInstruction | Exact direct scalar local/field and initial value; no result |
| SsaStoreInstruction | Exact memory Place and replacement scalar value; no result |
| SsaLoadInstruction | Exact memory Place and one scalar SSA result |

SsaProgram owns descriptors required by retained typed pointer types or
addressable locals, in source declaration order. SsaFunction owns its addressable
storage array. Entirely scalarized structs require neither. Storage objects and
memory Places are not SsaValues. AddressOf has a pointer result; there is no
SsaStructValue, aggregate copy, whole-struct dereference, or memory SSA token.

Promotion runs the existing initialization-dominated frontier/renaming algorithm
only over eligible CFG Places. Addressable scalar/field initialization instead emits
ordered SSA Initialize instructions in written initializer order. Subsequent
direct reads emit Load, even before any borrow call. Indirect reads/writes also
remain Load/Store. Calls may mutate any scalar/field reachable through their typed
pointer arguments. Later loads therefore read memory again; no invalidation,
caching, alias analysis, or forwarding is needed.

Block instruction order is semantic memory/call/trap order. No optimizer moves
or eliminates these operations. Initialize remains distinct from Store for
future initialization/replacement and ownership rules.

The standalone SSA verifier checks unique program struct/field authority and
function storage identities, supported canonical pointees, exact memory
projections, field value/result types, and matching AddressOf types. It checks
SSA operand dominance, including pointer values and parameters, and initialization
dominance before direct storage access or borrow. Each reachable initialized
storage must have one Initialize site per scalar local or field; an entirely unreachable local
may have storage without reachable initialization. A loop-local initialization
site executes each time control reaches it. Storage provenance ordinals also
reject a promoted block-parameter origin claiming the same addressable local.
Those copied origins are an overlap check, never runtime storage identity.

## Ownership and stage lifetime

Each stage translates descriptors and projections into its own objects. The
immutable semantic pointee type has no symbol/syntax backlink; TypedPointerType owns
its pointee. Fields weakly reference their containing descriptor. SSA storage
strongly owns its descriptor; direct Places own storage/field; indirect Places
own pointer value/field. Instructions own operands and independent result
objects. Results have no instruction backlink, so the memory graph has no
instruction/result/Place cycle.

After SSA construction, CFG Places and every upstream checked/Core object may
die. Standalone SSA verification and dumping need no CFG/Core/LLVM. After LLVM
lowering, SSA descriptors/storage may die; LLVM owns its complete physical
module. After object emission/linking, LLVM and compiler resources may die before
the executable runs.

Persistent references, broader address-of, escaping pointer results,
ownership-bearing native storage, and C structs must revisit the current lifetime proof, promotion
barrier, and aliasing contract explicitly. See
[ADR 0026](../decisions/0026-typed-struct-pointers.md) and
[backend realization](../backend/native-struct-storage-v0.md).

## Stored borrow qualification

BORROW-1 proves lexical pointer lifetime compatibility before Core construction.
Regions and BorrowProvenance belong only to the checked semantic model. An
accepted `Pair* p = &pair` uses CoreAddressOfValue followed by ordinary pointer
Initialize; reassignment uses Store. CFG and SSA use their existing address
values and operations with immutable DataPointerProvenance origin/region
snapshots on source addresses and dereference Places, without a checked-region
backlink or runtime lifetime metadata. Branch/null merges and loop
backedges use ordinary pointer block arguments.

The pointee remains address-taken for the whole function, so its fields cannot
promote even when the borrow is brief. Pointer-local storage stays promotable;
other, untouched structs still scalarize by field. Multiple stored mutable
borrows may alias. Native PTR, LLVM representation, and existing null guards are
unchanged. DPTR-1 applies these same rules to supported scalar locals and
generalizes storage into SsaAddressableLocal. See
[dereference Places](dereference-places.md),
[ADR 0027](../decisions/0027-lexical-borrow-regions.md), and
[ADR 0043](../decisions/0043-typed-data-pointers.md).
