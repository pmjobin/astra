# ADR 0127: explicit native nonnull contracts

Use `nonnull C` and `nonnull Resource` in initialized locals, direct native
parameters and owned results. Ownership qualifiers precede `nonnull`, as in
`owned nonnull C` or `borrowed nonnull Resource`. Existing unqualified references
remain nullable. This is declaration metadata over the existing exact nominal
type, not a new ABI type or a language-wide default migration.

A construction, promised native result, qualified parameter, or current local
`!= null` branch can discharge an obligation. Both sides of a join must prove it.
Short circuits, early exits and loop backedges retain their actual evaluation
order. Assignment invalidates the old slot's refinements and capture associations.
An earlier Boolean or mutable-field test cannot authorize a later nullable value.
The current source/Core adapters deliberately narrow direct locals and parameters,
not arbitrary stored Boolean expressions or unqualified mutable fields.

An owned Class field may also opt in. Its existing definite-initialization and
owned-transfer authority remains mandatory; every initial and replacement owner
must prove nonnull. This supports `property borrowed nonnull C item` over one
exact owned field through the existing pure receiver-projection contract. It
does not introduce a new borrow lifetime, alias or escape permission. Lazy caches
and borrowed setters are outside this qualified result slice.

The source adapter diagnoses checked-tree obligations. Core independently
reconstructs them from Core identities and effects. CFG computes a forward must
analysis over its definitions and actual edges, including checked success,
throw, cleanup and aborted argument reservations. Conditional facts preserve the
meaning of lowered short-circuit temporaries and invalidate changed slots. SSA
reconstructs facts from definitions, branch edges and phi arguments; entering a
block invalidates facts about its previous loop iteration. Promotion retains an
ordered verifier-only obligation for each explicit qualified local write, with
an exact-presence registry bound to its original block and instruction position. Move/release null bookkeeping does not assert a live
qualified write. All four adapters independently check qualified field transfers.

Declaration promises are one-way markers. Builders copy them into their own
models; a downstream verifier cannot erase one by setting a public Boolean to
false. The mechanical fact store interprets no upstream nodes. Ordinary owner,
borrow, definite-initialization, dominance and exception validators still run;
a nonnull pointer can be moved or dead and does not recover liveness.

Qualification is limited to concrete synchronous direct native definitions and
exact Class/Resource references. Strengthening raw pointers, Shared/Weak,
closures, interfaces, generic Class applications, generic definitions, async
suspensions and virtual/override contracts rejects. Unknown C results require an
explicit null branch. Imported or exported C signatures cannot claim the new
promise. No LLVM `nonnull` attribute or additional runtime null trap establishes
the guarantee; existing ordinary member guards and native/C ABI remain intact.

Independent model tests tamper with arguments, branch direction, field owner
selection and retained SSA obligations, require rejection, then restore the
valid model. Public Class/Resource programs qualify source admission, checked
failure cleanup, O0/O1/O2 and memory behavior. See the
[language guide](../language/non-null-references.md) and the open
campaign checkpoint for measured evidence.
