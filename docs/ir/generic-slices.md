# Generic slices before concrete Core

The semantic universe interns SliceType by exact element identity, including a
bounded plain-copy TypeParameterType element. Interning is not proof of eligibility.
`GenericSliceObligations` records signature-derived lexical tokens and supplies the
shared symbolic/concrete storage rule. Semantic and Core callers each resolve their
own exact field graphs and scope; concrete admission delegates to
`GenericArgumentTypes`/`CopyabilityAuthority` and `BufferElementTypes`.

The Core verifier independently checks that every obligation corresponds to an
exact direct T[] formal or owned T[] result, every such signature occurrence has
its obligation, no foreign token
is present, and every application satisfies the obligations even for an unused
body. Ownable cannot stand in for plain copying. The semantic signature pass
establishes all obligations before the body; local view declarations consume them.
Dumps expose `(slice-element #n T mutable-storage)` on parameterized definitions.

| Operation | Parameterized representation | Concrete materialization |
| --- | --- | --- |
| View parameter/local | SliceType<T>, borrowed contract and existing provenance | Canonical SliceType<E> and unchanged contract |
| len | SliceLengthValue | Existing int length operation |
| Index | SliceElementPlace with exact view/index/origin | Ordinary checked element Place |
| T load/store | Existing bounded plain-copy Load/Store/Initialize | Scalar/vector operation or complete StructSnapshot/StructCopy |
| T argument/result | Existing generic call and bounded value consumers | Existing scalar/vector channels or aggregate-v7 leaf transport |

TypeSubstitution handles the direct slice constructor. Semantic substitutions
use the universe's canonical slice factory. Independent call validation compares
one substituted element identity and still validates the actual canonical slice.
The monomorphizer interns by completed concrete element, so different definitions,
explicit/inferred requests, fixed-array producers and buffer borrows share the same
slice identity. Its existing registries still key instances by exact definition and
ordered type arguments. Private key snapshots and mutation/cycle checks remain.

Inference retains checked complete view expressions and transactional ownership
fragments at written argument positions. There is no target typing of a later
participating literal. Cached fragments commit with successful argument checking;
failed completion discards them. Generic forwarding observes the exact outer token.
Source labels, captures, pointer/count values, origins and proofs never enter keys.

The existing cloner remaps parameters, acquired record locals, element Places,
optional receiver provenance and local origin ordinals. It captures record leaves
through bounded producers, never an aggregate SSA value or an escaped element
pointer. Source/Checked universes can die before materialization; obligations own
only lexical tokens and disappear with their definitions. Concrete verifiers and
CFG/SSA see no unresolved slice application, proof or inference node.

Every concrete bounds association, view join, borrow interval and owner overlap
uses the ordinary rules. NABI uses the existing numeric/mask slice plans or
struct-elements-v11 record plans; T values use existing scalar/vector or
aggregate-v7 channels. Effective profile selection may be later when other features
require it. A local-only view does not alter unrelated signatures. Native plans own
immutable exact record shapes; identical PTR/count carriers do not equate text,
numeric and record views. Physical stride remains target authority.

No dictionary, runtime type descriptor, ownership acquisition, collection copy,
noalias promise, memcpy-overlap assumption, per-element allocation, hidden result
pointer, frontend sret/byval convention or downstream specialization is introduced.
Existing 1,024 instance and 256 application/dependency limits remain. See
qualification for independent malformed models,
stage lifetimes, exact equivalence, machine artifacts and measured costs.

[Generic owned arrays](generic-owned-arrays.md) separately authorize symbolic buffer
responsibility and allocation. Borrow-only specializations keep the contracts described
here and gain no owner slots or allocator calls.
