# Slice values

[Struct-elements-v11](../abi/native-struct-elements-v11.md) adds exact recursive element shape to record-slice plans while retaining PTR/I32 transport and mutable bounded borrowing. Numeric views, record views and deep read-only text descriptors remain distinct contracts.

SliceType is an independently retained immutable compiler type with exactly one
field: `element_type`. BuiltinTypes interns exact element identities; int/i32
share one slice identity. Runtime extent belongs to a value, never a type.
Numeric and record views use the shared BUFFER element qualification; read-only
text descriptors retain the separate ARGS contract. Stage verifiers independently
check admissibility, complete record graphs and canonicalization. Fixed arrays and
structs have no general Value representation.

| Stage | Construction | Length | Copy/merge |
| --- | --- | --- | --- |
| Checked | CheckedSliceFromArrayExpression | CheckedLengthExpression | initialized local, reference, exact assignment |
| Core | CoreSliceFromArrayValue | CoreSliceLengthValue; array length is int constant | ordinary local Initialize/Load/Store |
| CFG | CfgSliceFromArrayValue in ordered Evaluate | CfgSliceLengthValue in Evaluate | one SliceType local/captured value |
| SSA | SsaSliceConstructInstruction, one result | SsaSliceLengthInstruction | one SliceType definition/block argument |
| LLVM | `{ ptr, i32 }`, insertvalue | extractvalue field 1 | aggregate SSA phi |

Every constructor retains exact array storage/type, exact result SliceType,
optional paired start/count values, immutable LOCAL provenance, and a source
span. Full construction has no range operands and returns length N. Subrange
operands are scalar IntegerTypes. CFG captures start, then count, then executes
one potentially trapping construction; neither operand can be delayed until
after validation. The usable result appears only after the range checks.

The range contract is `0 <= start <= N`, `0 <= count <= N - start`. Core diagnoses
malformed direct constant ranges; later stages preserve runtime validation even
when no general constant folding exists. Empty views are ordinary SliceType
values with extent zero and lexical authority. No null SliceValue exists.

Checked BorrowProvenance.for_expression recognizes array construction, native
borrowed parameters and stored slice reads. A parameter uses the function region
and retains its BORROWED_NOESCAPE contract. A construction uses the array's region;
a local read conservatively uses the slice local's own region. Initialization
and rebinding apply existing BORROW ancestor/same-region rules. Core retains an
immutable DataPointerProvenance snapshot with local/region ordinals, never a
checked symbol or region-tree link.
After legality is checked, later stages need no second lifetime engine or runtime
metadata. Bare lexical blocks are CheckedBlockStatement/CoreScope and reuse
existing region, cleanup and CFG continuation handling.

A source slice is never split into independent pointer and length locals. Branch
selection between `T[4]` and `T[8]` yields one `T[]` block argument; loop rebinding
carries that same semantic value. Copying retains shared storage, including
intentional mutable aliases. Promotion never makes the backing ArrayType a
whole value or creates synthetic element locals.

LLVM maps local SliceType directly to `{ ptr, i32 }`, bypassing the NABI mapper.
Full construction gets element zero's address and N. Subrange start/count are
losslessly sign/zero-extended to signed i64 for exact mathematical comparisons.
The start guard precedes subtraction; the count guard precedes any element GEP.
Only on a nonempty path is the validated start used for plain array GEP. The
empty edge supplies null to a backend-only base phi, then base/extent are inserted
into a fully initialized aggregate. Count narrows to i32 only after proving its
bound. This introduces neither poison nor undef, source pointer arithmetic,
one-past pointers, a slice runtime library, nor stable ABI.

Every stage is complete after destruction of its predecessor. LLVM has no
remaining SSA/type/source references after lowering. Guard/empty-path splits
update LlvmBlockState.end so later phi incoming blocks name actual physical
predecessors. SLICE-BOUND-1 admits one exact borrowed native slice parameter at
each stage. NativeSliceType groups its physical PTR/I32 components under one
parameter ordinal in slice-v5. LLVM expands the group for calls and reconstructs
the existing aggregate at entry. No semantic pointer/count locals or paired SSA
definitions are introduced. Copies, forwarding and recursion use ordinary whole
values. CABI/VAPI and slice results remain unsupported; exact contracts and
signature/storage guards enforce the current noescape boundary.

See [slice places](slice-places.md), [language](../language/slices.md),
[ADR 0046](../decisions/0046-bounded-borrowed-slices.md),
[ADR 0047](../decisions/0047-native-borrowed-slices.md),
slice qualification and
boundary qualification.
