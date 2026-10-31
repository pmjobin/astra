# ADR 0079: Generic borrowed slices

Status: Accepted for ASTRA-GEN-SLICE-1.

GEN-COPY supplies exact lifetime-neutral value copying, while BUFFER and
STRUCT-ELEM already supply mutable bounded collection storage. Ordinary source
algorithms need to borrow that storage without copying or acquiring the collection.

Admit one new formal pattern: `T[]`, where `T` is a plain-copy function type
parameter. Plain and explicitly `borrowed T[]` parameters use the existing
mutable, aliasable `BORROWED_NOESCAPE` contract. Their bindings are immutable.
Derive an exact scoped element-storage obligation from the signature before
checking its body. A local `T[]` can only copy an existing compatible view under
that premise. Local uses cannot strengthen a signature.

Copyability and mutable storage remain separate authorities. Concrete arguments
must satisfy GEN-COPY and the accepted BUFFER/STRUCT-ELEM composite eligibility
rule with the exact field graph. Reusing that composite rule does not make zero
initialization a consequence of copying. These algorithms borrow initialized
storage; they allocate nothing. Text slices retain their separate read-only deep
borrow contract and do not match this pattern.

Infer one exact element observation from each participating `T[]` argument.
Combine it with direct `T` and owned `U` observations in written order, without
literal target typing, common-type selection or recursive pattern unification.
Checked argument expressions and ownership fragments are retained transactionally
and reused once. The completed type argument is the element, never the collection.

Retain the canonical SliceType constructor in parameterized representations.
Scoped obligations contain only exact lexical type tokens. Existing length,
indexed Place and bounded plain-copy nodes suffice: materialization substitutes
and interns the concrete element identity, then chooses existing scalar/vector or
record snapshot/copy operations. No source body is rechecked. Existing concrete
Core, CFG, SSA and independent native plans remain authoritative. Generic instance
keys and the 1,024/256 limits are unchanged.

A dedicated generic slice class, runtime descriptor, borrowed aggregate result or
universal aggregate SSA value would add contracts this use does not need. Extending
the existing slice representation preserves its pointer/count grouping, guards,
backing origins and native profile selection. The small substitution matcher checks
one exact element identity; it is not a layout comparison or a pattern solver.

Ship `fill` and `swap_elements` as unprivileged, explicitly selected source in
`lib/astra/base/slices.astra`. Index failures use language traps. No failure provider,
prelude, reserved name or autolink rule is introduced.

Deferred: direct Ownable borrowing; public Copy/Move/Element capabilities; string or
view-valued T; generic owned buffers/allocation; slice results; constructed/nested
formal patterns beyond T[]; unknown-element members; generic methods/classes;
iterators, foreach, resizing; generic zero/constructors; C collections; modules;
new targets; and external CAD migration.

See [language](../language/generic-slices.md), [IR](../ir/generic-slices.md),
[library](../library/slice-algorithms.md) and qualification.
