# Borrowed text-slice values

ARGS-1 admits the canonical `SliceType<StringType>` in native parameter and local
view positions. Slice identity does not encode ownership or a second string
identity. `SliceElementAccess.READ` describes descriptor-slot permission;
`deep_borrow` requires stable table storage and stable validated payload bytes.
Array and buffer allocation eligibility remains under `ArrayType` and
`BufferElementTypes`, which continue to exclude strings.

Semantic, Core and CFG retain one typed outer view and one typed string result
per element read. Existing slice length and element-place nodes carry the exact
slice identity, integer index and lexical provenance; text element provenance
also records the deep table/payload obligation. Core construction snapshots that
contract and ordinary monomorphization preserves it. These models contain no
argv, allocator, platform path or startup symbol.

The origin proof uses existing per-write equations. Parameters introduce bounded
borrowed leaves; literals and proven static-result calls introduce static leaves.
Local reads capture the current origin version. Copies and branch/loop joins
preserve all incoming obligations; reassigning a local cannot rewrite a saved
copy's equation. Extraction copies the captured slice's backing origin to the
ordinary string. Ungrounded cycles are invalid and a borrowed input prevents a
static-result proof. No visible caller can strengthen a callee's parameter origin.
All text-slice producers in this subset are parameters, so their deep backing
outlives local descriptor slots throughout the invocation.

CFG captures the list before its index and produces an explicit bounds result
for that exact captured view. SSA preserves one outer `SliceType` value, one
inner `StringType` load result, and complete values on edges/block parameters.
The verifier checks the exact bounds/view association and ordered definitions,
rejects descriptor stores and insufficient deep provenance, and reconstructs
origin equations independently. No universal aggregate Astra SSA value is added.

LLVM represents a descriptor in memory as a natural `{ptr,i32}` record and loads
one corresponding pair only after the bounds check. GEP uses that record type;
the target data layout determines stride. Existing final-block tracking supplies
actual predecessors after bounds and numeric guard splits. There is no new
`nonnull`, `noalias`, lifetime-end, over-alignment, or global optimizer promise.
Read stability is a borrow contract, not concurrent atomic mutable storage.

Native plans and the independent entry plan retain only immutable type/shape
leaves and source provenance. LLVM retains its own values, selected entry kind
and target-layout witness, not the source function or its earlier stage graph.
Standalone models test malformed groups and origins without relying on frontend
success; pipeline tests destroy predecessors before verifying successors.
