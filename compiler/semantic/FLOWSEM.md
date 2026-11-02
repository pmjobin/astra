# Native nonnull and aggregate flow

FLOWSEM extends the retained CheckedIndex → FlowIndex graph. The new consumer
opts into semantic adapters; `astra-flow/1` and the original OWNFlow-6 consumer
retain their historical eligibility. Production C0 remains the independent
enforcing reference. This is source analysis, with no Stage 1 or downstream
Core/CFG/SSA/LLVM qualification implied.

The source-authored corpus and full C0 stage outcomes were frozen before native
implementation. Four initial expectations were wrong: owning-record member
replacement/extraction, nested constructor leaf writes, and two combinations of
nonnull checking with record initialization. Their original source and failures
remain in `flowsem7/frozen-initial`; corrected sources and expectations are in
`frozen-qualified`. Tooling-index success is never an enforcing receipt.

| Family | Admission | Explicit frontier |
|---|---|---|
| Nonnull | exact native nongeneric Class locals/parameters, owned constructions and direct nonthrowing qualified results; null guards, negation, short circuit, joins, structural loop fixpoints, overwrite and owner invalidation | Resource/foreign/generic/Fn/member and property contracts; captured Boolean implications |
| Records | concrete native structs with scalar/bool leaves, nested structs, owned numeric buffers and empty native Class children; explicit aggregate initialization, complete root copies/moves, scalar member reads/writes, ordered automatic cleanup | nonliteral nested-field copies, owning-member extraction/replacement, generic fields, fallible construction, borrowed record channels |
| Classes | direct native constructor, scalar/bool fields and owned empty-Class/buffer children, explicit assignments, branch completion and nonnull owning-field requirements | constructor loops/explicit returns, standalone receiver escape, custom destructor, inheritance, methods/properties/virtual dispatch, allocator/concurrency/foreign metadata, nested mutable Class fields |
| Identity | exact program/function, original checked use, SymbolId/TypeId, receiver root and declaration path | matching names or equal source bytes confer no identity |

Responsibility stays OWNED=1/MOVED=2/RELEASED=4, with OUT_OF_SCOPE=8 and
UNINITIALIZED=16 bookkeeping. Nullness has its own NULL=1/NONNULL=2/UNKNOWN=3
possibility domain; only exactly 2 proves a demand. Field leaves retain their own
initialization/responsibility sets. Reachability is separate. A declared promise
is checked at each incoming boundary; it never repairs a moved owner or missing
leaf. Unproved functions retain named source spans and publish no safety proof.

The original 47 source contents remain byte-identical across the corpus freezes.
Matching the actual C0 first-error contracts moved constructor loops, constructor
returns and standalone receiver escape into explicit deferrals. Field token
anchors enrich the independently authored initialization expectations without
changing source bytes. C0 does not expose the native lattice; these expectations
are separate from its enforcing outcomes.

Three later source-authored witnesses extend that freeze: inferred-local
overwrite followed by a fresh guard, a stale copied guard after overwrite, and
a nested-field record copy. The first two distinguish inferred qualifier
metadata from a source-declared promise. The last remains UNSUPPORTED_EFFECT
until a declaration-bound leaf-copy transition exists. Whole compiler-source
execution exposed this boundary and an unqualified implicit receiver; neither
is converted into a safety proof. The original failures and rebuild receipts
remain in external task evidence.

Class construction validates exact constructor argument types and channels.
Each aggregate has a declaration-bound tree of field identities, including
distinct paths when the same nested nominal type occurs twice. Leaf writes,
whole-value completion, moves and scope retirement run on the owner CFG.
Completeness and responsibility remain separate obligations: an owning record's
initializer retains its original reason 20 while its declaration records reason
19. Constructor completion adds a source-located reason-20 lifecycle obligation.
The legacy consumer keeps its original checked-use contract.

`astra-flow/2` adds NULL, FIELD and FIELD_STATE rows; PROOF still names the
original checked node and reason. Null queries return NULL=1, NONNULL=2,
UNKNOWN=3, bottom=0, invalid identity=-1 or unavailable=-2. Field queries expose
the leaf responsibility sets: definite initialization requires exactly 1;
possible initialization includes bit 1. A moved root or an unproved nullable
Class receiver cannot grant an available field fact. Public semantic queries
reconstruct the source graph and solve it again before trusting mutable stored
tables. This is a model-corruption check, not an independent downstream verifier.

Only a complete admitted program publishes semantic proof overlays. Deferred
compiler-source observations retain original unclosed 18/19/20 uses even when
the new builder can reconstruct more operations. Changes in named admission
deferral counts are not themselves proof closures or a coverage percentage.
The fact-cell ceiling includes owner, loan, null-value and field inventories;
row/step exhaustion remains FLOW_RESOURCE_EXHAUSTED with no published proof.

Qualification results will be recorded here after final-source execution.
