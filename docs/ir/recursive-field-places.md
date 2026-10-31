# Recursive field Places

[Struct collection elements](struct-elements.md) extend the existing recursive Place graph with indexed Array/Slice roots. Indexed methods internally address that Place with an exact ReceiverType; source element/subfield address-taking remains excluded.

A projection has the rule `base : Place<S>, field.owner == S → Place<field.type>`.
The owner and result type must match exactly. Field spelling and byte offsets
never establish storage identity. Struct-valued intermediate Places are storage
identities, never loads or whole-aggregate Values.

```text
FieldPlace(
	base = FieldPlace(
		base = LocalPlace(o),
		field = Outer::inner),
	field = Inner::x)
```

CheckedFieldPlace retains its CheckedPlace base, exact StructFieldSymbol, result
type and source span. CheckedLocalPlace and CheckedDereferencePlace provide roots;
existing receiver-field Places also compose. Historical direct leaf checked forms
remain compatible. CheckedStructInitializer is a non-expression tree whose fields
retain either a nested initializer or one exact leaf expression in written order.

CoreFieldPlace and CfgFieldPlace retain the same recursive rule with stage-owned
field descriptors. Local projections are canonical in preorder: local ordinal,
then recursively declaration field order. Repeated use of one path shares the
same canonical identity; sibling subobjects retain distinct bases even when they
share an Inner::x field descriptor. Nonlocal projections recursively retain the
pointer/receiver Place root. Verifiers check the complete base chain, exact field
membership/owner, result type and program/function ownership.

CoreStructInitialize targets an exact struct-valued CoreFieldPlace and owns
source-ordered child initialization statements. It creates no CoreValue.
Verification recursively requires every child once and complete visibility of
root storage. CFG lowers this tree to ordered ordinary leaf Initialize operations,
retaining all recursive projection descriptors. Scalar/vector leaves alone become
values; no aggregate Initialize-with-Value or memcpy is synthesized.

Promotion uses exact CfgPlace keys in the existing definition and dominator
architecture. Intermediate StructType Places never promote. Scalar/vector leaves
of non-addressable roots do. Copied root ordinals and field-ordinal sequences
serve only SSA debug provenance and deterministic block-parameter ordering;
concatenated display names never identify definitions. Whole Inner/Outer SSA
values do not exist.

For memory roots, SsaFieldPlace itself owns a recursive SsaMemoryPlace base.
Existing direct/indirect root forms retain their prior representation and dumps.
SSA initialization identity compares exact root storage and exact field descriptor
sequences, distinguishing sibling projections through the same inner field.
Storage completeness and dominance checks apply to all leaves. Descriptor retention
includes transitive embedded structs and remains independent of Core/CFG lifetimes.

The backend's single memory_address routine recursively handles local storage,
dereference and field projections. It never loads an intermediate aggregate.
LlvmStructRegistry declares needed nominal LLVM types before filling element
bodies, preserving declaration order and exact nested/vector/double element types.
LLVM/DataLayout retains physical layout authority. No aggregate ABI or runtime
metadata is implied.

Semantic and Core cycle checks walk exact by-value struct dependencies independently;
CFG/SSA standalone verifiers also reject cycles and missing concrete descriptors.
Typed pointers would not add by-value edges, but typed pointer fields stay rejected
under baseline policy. Class fields and lifecycle semantics are unchanged.
GEN-STRUCT-1 [generic aggregates](generic-structs.md) materialize into ordinary concrete fields and reuse this machinery before CFG.

## Whole subobject copies

[StructCopy](struct-copy.md) retains two exact recursive Place trees. Nested
StructType fields recurse in declaration order and vectors are atomic whole
leaves. Core→CFG stabilizes both roots and captures all source leaves before
writing destination leaves. Canonical local projections remain promotion keys;
indirect roots use ordinary recursive memory addressing. Copy creates no general
aggregate Value and does not itself request addressability.
