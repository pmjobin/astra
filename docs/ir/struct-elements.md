# Record collection IR

The shared semantic authority asks separate storage, copyability, destruction and
zero questions over each stage's exact field graph. Type interning does not certify
that graph. Per-query traversal detects incomplete/cyclic records and memoizes
completed shared subgraphs without retaining a type universe.

Checked and Core retain bounded struct snapshots, call producers, copies and
producer stores. `ArrayStructInitializerSyntax` is an expected-type storage entry,
not a general aggregate expression. Core `ArrayInitialize` retains complete typed
entries with exact indexed destinations, written named-field order or a bounded
producer. No target byte offsets enter Core.

An ArrayElement/SliceElement Place is the indexed root of the existing recursive
FieldPlace graph. A projected receiver uses the existing address operation with
an exact live ReceiverType; it is not a source pointer escape. Verifiers check
containing type, field membership, canonical element identity, bounds/view
association and lifetime at the point of use. Owned-field borrows follow every
recursive projection to its containing receiver.

CFG completes one fixed-array entry at a time. It captures producer leaves before
entry stores and retains existing scalar/vector initialization operations. Array
storage becomes readable/borrowable only after N complete entries. Call-result
entries require complete, exact leaf consumption adjacent to the entry store.
Whole-record assignment validates its destination before lowering its producer;
all source leaf evaluations precede copy-generated writes.

SSA has ordinary scalar/vector definitions and existing buffer PTR/count groups.
It shares the captured indexed root across leaf projections. Physically addressed
array storage remains addressable; copied ordinary locals can still be promoted.
There is no StructValue, aggregate phi or required temporary aggregate alloca.
A completed snapshot has no backing address. Live projected receivers and
destinations recheck their owner/projection validity through later evaluation.

Native plans own copied nominal declarations and immutable recursive shapes;
they retain no SSA, Core, checked, generic-application or syntax graph. Target
qualification separately computes natural physical layout and compares every
field's identity, order, allocation size, ABI alignment and offset against LLVM.

LLVM loads/stores each semantic leaf through the captured root. Guards precede
address formation. Shared address caching is restricted to the current physical
continuation; guard-split blocks update the continuation used by downstream phis.
Record allocation checks count times allocation stride, and indexed address
lowering checks index times stride in i64, including the signed address-range
bound. No noalias promise or padding-copy semantics are added. The existing
`nobuiltin` allocator policy retains observable OOM behavior under optimization.

Standalone stage tests and pipeline lifetime tests live in `tests/struct-elem-1`.
See qualification for tested evidence and limits.
