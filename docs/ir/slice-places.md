# Slice element Places

[Record elements](struct-elements.md) reuse SliceElementPlace as the root of recursive FieldPlaces. Each projection verifies exact type membership and the same captured bounds/view association. Complete source snapshots are distinct from live receiver/destination addresses.

SliceElementPlace is a distinct writable indexed storage projection. It retains
one evaluated slice value, its exact SliceType and element type, an integer
index, runtime length authority, immutable provenance, and source span.
ArrayElementPlace instead retains direct array storage and a fixed bound.
VectorExtractValue has no writable storage authority. Similar brackets never
override these distinctions.

SLICE-BOUND-1 also permits a borrowed native parameter as the source view.
Its provenance is PARAMETER in the function lexical region, and it retains the
same mutable place and runtime bounds rules. Trusted native callers supply
well-formed slices, so a successful callee bounds check needs no separate null
check. See [native slice channels](../abi/native-slices-v5.md).

| Stage | Projection | Validation |
| --- | --- | --- |
| Checked | CheckedSliceElementPlace | exact SliceType/index; BorrowProvenance |
| Core | CoreSliceElementPlace | exact base/element/index; provenance snapshot |
| CFG | CfgSliceElementPlace | CfgSliceBoundsCheck for the captured view |
| SSA | SsaSliceElementPlace | SsaSliceBoundsCheck result dominates its uses |
| LLVM | plain element GEP | runtime extent guard precedes address/load/store |

Read order is slice expression, index expression, bounds validation, Load.
Write order is slice expression, index expression, bounds validation, RHS, Store.
The view is captured as one value before index effects; both base and length
belong to that same value. The index evaluates once for each written access.
Invalid LHS bounds suppress RHS evaluation, including calls and short-circuit
regions in the RHS.

CFG always emits a SliceBoundsCheck, including constant indices. Its validated
integer result is associated with the exact captured view. CFG and SSA verifiers
reject missing, mismatched, late or nondominating validation, so a check for one
slice cannot authorize access to another. The result retains the original index
type. Unlike fixed array indices, a constant slice index alone proves no extent.
Only physical lowering may optimize a separately proven bound.

Bounds are `0 <= index < runtime_length`, using exact mathematical IntegerType
meaning. The backend losslessly extends all current signed/unsigned operands to
i64 and compares against the captured non-negative i32 length. Invalid paths
call llvm.trap and end in unreachable. Only the valid continuation extracts the
base for a plain GEP over exact element type. Empty slices always fail before
base use. A null physical empty base never becomes a source null slice or a
nullable typed object pointer.

Scalar accesses reuse exact i8/i16/i32/float memory. Numeric vector accesses are
one exact vector Load/Store upstream and one vector LLVM memory operation;
backend legalization may split machine transfers. Subrange start and element
indices measure whole vector objects, never lanes or bytes. `view[i][2]` is a
whole-vector Load followed by VectorExtractValue/Instruction; it has no LanePlace.
`view[i] = insert(view[i],2,x)` is the whole-vector update form. Separate source
index spellings remain separate evaluations.

Array storage remains the alias authority: direct array writes, slice writes,
copies, and overlapping slices observe the same objects. Slices impose no
exclusivity. Element alignment and stride derive from backing array DataLayout;
no source alignment number or atomicity guarantee is added. Unoptimized slice
GEPs are plain, without inbounds. Guard and empty-path splits use the established
physical final-block authority for branch, loop and short-circuit phi edges.

No slice element address-of, pointer extraction, pointer arithmetic/indexing,
unchecked indexing, raw pointer construction or runtime helper exists.
See [slice values](slice-values.md) and [array places](array-places.md).
