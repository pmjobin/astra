# Typed dereference Places

DPTR-1 extends TPTR-1's explicit memory architecture. `TypedPointerType` owns
one exact immutable `SemanticType pointee`; raw void* is separate. Shared type
objects have no checked symbol/syntax backlink. Exact object maps translate
locals, fields, parameters, and functions; no stage resolves pointees by name.

The capability `is_typed_data_pointee()` admits integer, f32, and native struct
types, plus supported numeric VectorTypes.
`is_directly_dereferenceable_value_type()` admits integer, f32, and numeric vectors.
This keeps pointer type admission separate from whole-value load capability.

## Place authority across stages

| Stage | Address and dereference authority |
| --- | --- |
| Checked | `CheckedAddressOfExpression` owns exact LocalSymbol (including its type/region), TypedPointerType, and span; BorrowProvenance is derived from that exact local. `CheckedDereferencePlace : CheckedPlace` owns the pointer expression, exact pointee type, provenance, and span. `CheckedLoadExpression`/`CheckedStore` consume that Place. |
| Core | `CoreAddressOfValue` refers to exact address-taken CoreLocalPlace. `CoreDereferencePlace : CorePlace` owns CoreValue pointer, exact pointee SemanticType, provenance snapshot, and `traps_on_null`. Existing CoreLoadValue/CoreStore consume it. |
| CFG | `CfgLocalPlace.address_taken` survives from Core. `CfgDereferencePlace : CfgPlace` owns the stage's pointer value, exact pointee type, provenance, and null-trap contract. Existing Load/Store handle it. |
| SSA | `SsaAddressableLocal` owns type, optional exact SsaStruct descriptor, storage ordinal, and copied local source information. `SsaLocalMemoryPlace` and `SsaDereferencePlace` extend SsaMemoryPlace alongside SsaFieldPlace's direct/indirect projections. |
| LLVM | One backend alloca per retained storage object; ordinary opaque pointer values; load/store operations carry the exact scalar or fixed-vector physical type and explicit null guard. |

`DataPointerProvenance` is an immutable snapshot of origin kind (null, local,
parameter), origin ordinal, and guaranteed lexical region ordinal. Checked
BORROW-1 region objects prove outlives before lowering; the snapshot records that
proof without retaining checked locals, parameters, or region trees. Ordinals
are function-scoped provenance/debug labels, never runtime storage identity.
Source-produced addresses and dereferences retain these snapshots through SSA.
Legacy synthetic AddressOf model constructors may omit the optional snapshot;
dereference Place constructors require it. There are no runtime borrow counters
or region checks.

The existing Core/CFG name `semantic_type` is stage-independent type authority,
not permission to retain checked graphs. Destruction-witness tests destroy the
checked graph before Core, Core before CFG, CFG before SSA, and SSA before
ABI/LLVM artifacts are consumed.

## Addressability and promotion

```text
LocalSymbol.address_taken
	→ CoreLocalPlace.address_taken
	→ CfgLocalPlace.address_taken
	→ SsaAddressableLocal
	→ backend alloca of exact T
```

The mark is static across the checked body, including late and unreachable
address expressions. Addressable scalar/vector initialization is one explicit
Initialize site; each direct read/write subsequently uses Load/Store on
SsaLocalMemoryPlace. Pointer access uses a DereferencePlace for the same live
object, without compile-time points-to identification.

| Source storage | Astra SSA |
| --- | --- |
| Scalar/vector local with no address taken | Ordinary promotable value, including block arguments |
| Address-taken integer/f32/numeric-vector local | Explicit storage and Initialize/Load/Store |
| Typed-pointer local | Ordinary promotable pointer value |
| Untouched struct's scalar field | Ordinary promotable field value |
| Address-taken struct's field | Explicit field memory |
| Dereference | Explicit memory Place; never promotable |
| Vector lane extraction | Value operation; not a Place |

There is no shadow SSA value for an addressable scalar or vector local. Calls may mutate
aliased storage; the next direct read reloads it. Multiple aliases need no
exclusivity or alias analysis. A loop-local Initialize executes each iteration.
The verifier rejects duplicate initializers, use before initialization, invalid
SSA dominance, and promoted source origins overlapping addressable storage.

## Evaluation and null authority

Value context lowers `*p` as DereferencePlace → Load → Value. Assignment lowers
as Store(DereferencePlace, RHS). CFG captures the pointer base in an
EvaluateInstruction before lowering the RHS, including RHS calls or short
circuit, so its source evaluation occurs exactly once and first. The RHS
finishes before the actual guarded store. Existing struct `p->field` assignment
retains its accepted RHS-first target evaluation behavior.

Core/CFG/SSA dereference Places expose an unconditional `traps_on_null` contract.
CFG does not need additional source successors for backend memory guards. LLVM
uses the established `guard_nonnull` operation and records each Astra block's
final physical LLVM block for outgoing edges and phi inputs:

```text
pointer evaluation → RHS (store only) → compare pointer with null
	→ null: llvm.trap, unreachable
	→ non-null: exact load/store, remaining operations and terminator
```

Every null path traps before physical access. Short-circuit source CFG can skip
the whole dereference; eager bool operations cannot. Tests inspect branch,
loop-backedge, and short-circuit phi predecessors against actual physical edges.
Null guards require no redesign of predecessor authority, ownership cleanup, or
the non-unwinding trap policy.

## Verifiers and backend realization

Core/CFG/SSA validate canonical supported pointer identity, exact supported
pointee, address-taken direct local targets, matching address/load/store types,
provenance shape, initialization, and dominance at the applicable stage.
Malformed bool/mask-vector/resource/void/nested typed pointers, mismatched widths,
whole struct dereference, and Initialize through an indirect Place reject.

NABI erases every TypedPointerType to existing PTR after source signature checks;
profile selection is unchanged. CABI rejects typed data pointers. LLVM realizes
PTR as opaque `ptr`, but obtains alloca/load/store types from the retained exact
pointee authority: i8, i16, i32, float, or exact numeric fixed vector. No source cast, GEP, numeric conversion,
fast-math, readonly, or noalias assumption is needed for scalar dereference.

Backend natural alignment is justified by direct local construction and exact
native forwarding. No stable numeric alignment or object layout is promised.
Numeric vector memory reuses this hierarchy unchanged; see
[whole-vector memory](vector-memory.md). Unaligned and foreign memory remain deferred. See [ADR 0043](../decisions/0043-typed-data-pointers.md)
and qualification.
