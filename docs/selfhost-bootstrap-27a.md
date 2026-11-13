# Initial native compiler bootstrap (27-A)

This checkpoint requires an unchanged C0 to produce a genuine Astra compiler,
then that compiler to translate the identical frozen compiler sources into a
working Stage2. A C0 seed, a linked compiler service, or a successful link alone
does not satisfy the checkpoint. Final convergence belongs to 27-D; release
qualification belongs to 28.

The authorized initial revision is `26542cf0760b788fcf56e46a375408540cf37f31`,
tree `ddaefe532c37a816fbebc4acca7ccc5aa5a246d6`. The submission SHA-256 is
`5f347d59b807d08f4c488d5917869b0e2dfe33652ff995be11a48392fa5bd6a1`.
The accepted predecessor report is 17,838,741 bytes at
`a33409156483fdb2ba70572997ac221e68454f6c5bc332ea3537327605beac00`.

The pre-edit gate authenticated its 238 safe members, 237 indexed payloads,
208 changed-source Git blobs, and ten-piece 16,161,716-byte evidence transport
at `8ee496350569b44bc99bd8867e9882149a90aec5ae78dfd2879f9519cca91808`.
The installed publication record and a new separate after-delivery G12 were
checked before source edits. The latter rebound original/current O0/O2 source
products and repeated original flow-number C0/Astra LLVM/object/link/execution
and strict returning Valgrind checks. Receipts are under
`~/Workspace/codex/work/astra/runtime/selfhost27a/G0/`.

The internal predecessor audit's G11/G12 remain PENDING at its creation time,
with `full_milestone_credit=false`; the new host receipt is separate. The
accepted R5 sequencing exception does not assert original ordering compliance.
Historical PARTIAL, failed/stopped receipts, and predicate26 DEFERRED remain
historical. The predecessor ZIP has a read-only byte-exact runtime copy.

The pre-edit preservation check matched 451 protected paths, 6,622 donor files,
1,044 historical proof hashes, six workflow files, fourteen hooks and Git
settings. The E25-A-v1 proposal, public C ABI, generic256 and SSA8M ceilings
remain unchanged. Host LLVM23.1.5 is distinct from the authenticated existing
read-only LLVM23.1.4 capsule used for execution.

## Driver and graph

`compiler/driver/main.astra` implements a bounded GNU/Linux x86-64 compiler CLI:

```text
astrac [--emit-llvm|-c|--check] [-O0|-O2] -o OUTPUT [--] FILE...
astrac --help
astrac --version
```

Sources and their library dependencies are explicit. `--check` needs no output.
Unsupported flags fail. The driver loads buffered files, constructs the actual
parser/semantic/Flow/Core/CFG/SSA pipeline, invokes independent verification,
and emits LLVM or native objects. Its diagnostics identify source paths and
half-open UTF-8 byte offsets. Successful output uses the existing bounded atomic
LLVM writer. Optimization follows physical source verification and uses LLVM's
verifier; the independent source checker is not applied to transformed IR.

The entry uses the already supported native `int main()`. The small
`compiler/driver/arguments.c` provider captures glibc's ELF init-array arguments
and exposes their exact bytes. Astra copies and validates UTF-8 and owns all
option parsing, source processing and compilation. This C provider performs no
Astra lowering and invokes no other compiler. Its independent observer compared
real argc/argv, empty/spaced/UTF-8/long arguments and bounds, including a strict
unsuppressed Valgrind run.

The graph is independently derived from tracked Git and the existing explicit
library recipe: 196 compiler Astra files including the driver, ten Astra
libraries, five existing platform providers, the LLVM C bridge, and the argument
provider. Archived platform witnesses outside the actual command receive no
translation credit. No test entry is included in the compiler source graph.
The packet's 208 changed snapshots are not used as the compiler population.

`tests/selfhost-bootstrap-27a/build.py prepare` freezes source bytes from an
explicit Git revision and emits the identity/snapshot/scope files consumed by
the existing `accelerate.py compile` and `compile-plan.py`. Run all recipes in
the authenticated capsule with explicit `--build` and `--runtime` roots under
the project work directory. The `rebuild` phase invokes its actual `--producer`
on that same frozen list, independently verifies LLVM, creates both O0/O2
objects and linked ELF products, and records hashes, commands and GNU time.
It never uses C0 as a runtime delegate for a subsequent generation.

The bounded diagnostic interface reports Typecore errors with source byte
ranges. Ownership refusals in later Flow/SSA verification currently identify
the rejecting phase without a source range. The qualification checks their
exact messages and independently confirms the invalid program with C0; it does
not claim those separate diagnostic systems use identical wording. Syntax,
initializer-type and unhandled-error byte positions are cross-checked against
C0 line/column positions, including a UTF-8 source prefix.

## Initial failure and correction

The first native preflight constructed 323,088 Flow nodes and then rejected the
new driver. A read-only native debugger localized the rejection to `astrac_run`.
A small diagnostic reproducer using its exact frozen option-parser body exposed
the rejected expression: `println_stderr(error.message)`. The caught message's
text view was recovered, but Typecore's surrounding pending call still had no
result type. The option-loop conditional owner move passed both focused probes
and was not the cause. A slower whole-source return trace reached its bounded
timeout; that stopped receipt is preserved without credit.

Recovery now admits the independently sourced caught-message argument only for
synchronous free calls with exact nonconsuming inputs and copied scalar/void
results. The producer leaves CheckedIndex unchanged. The separate type consumer
reconstructs declaration, signature and argument facts, and the Flow consumer
checks the refined call against its retained source. This grants no owning
result, consuming argument, method, foreign-call or checked-effect permission.
The regression also has an unchanged-C0 native/strict-Valgrind oracle.

The seed2 executable then exposed a separate payload-call obligation: the
caught-message view was not admitted by the borrow consumer. Read-only native
traces showed that both the type verifier and refined-call verifier accepted
the facts before this later refusal. The consumer now binds the message to its
actual caught Error owner, requires the owner in the same function, and retains
all other-argument borrow preservation checks. Only nonthrowing, nonconsuming
string channels with copied numeric, bool or void results qualify. Core and SSA
retain their independent owner-liveness checks.

An initial small test invocation included an unused `Vector<T>` library; the
existing closed-template rule correctly refused that unused open declaration.
The focused fixtures now name their actual errors/text dependencies. This does
not filter or reduce the canonical compiler graph, which instantiates Vector
and still includes all 196 compiler and ten library sources.

## Current qualification state

The 196+10 source graph frozen at
`a728c39541587f2892f974983e502be3775b2416` produced the real O2 `seed2/astrac-stage1`
ELF through unchanged C0 in 2651.568606465 seconds. Its SHA-256 is
`9cecfea33f9bcfdc343a4eed5bfba1a21f42d5ba6c67d0a3753c88a239686293`.
Its help/version commands run, but the focused compilation exposed the separate
borrow-consumer failure above; that seed receives no self-build credit.
The corrected full live source passed another C0 semantic check in 57.848807225
seconds before the next freeze. Native driver compilation qualification, actual
Stage1-to-Stage2 regeneration and final behavioral/memory qualification remain
pending. No 27-A PASS is claimed by this intermediate finding.

While the corrected seed was building, seed2 independently produced executable
O0/O2 objects for a minimal source and passed strict unsuppressed compiler
Valgrind. Eleven further valid source populations (original flow-number,
text-builder growth, derived errors, fixed slices, counted C import, shared
replacement errors, record arrays/results, separate owned/borrowed calls, a
minimal program and UTF-8 multifile calls) passed C0 differential native checks
and strict returning memory checks. Seven invalid populations, including alias
overlap, refused with exact phase-specific diagnostics and preserved output
sentinels; compiler failure cleanup passed strict Valgrind. These receipts under
`seed2preflight2` are explicitly single-stage preflights. They exclude the
separately recorded caught-message refusal and give no Stage2/self-build credit.

## Later pre-release work

27-A adds no syntax or ownership-default migration. The agreed 27-B/C target
remains ownership-default fields/results, typed local inference, compound
assignments, numeric literal forms, trailing commas, expression records/bodies,
named arguments, match expressions/nested patterns, typed interpolation,
first-class ranges and checked slicing, lazy adapters/reducers, fixed no-heap
collection, materializing comprehensions and idiomatic compiler/workload cleanup.
`(20..=80).step_by(5).collect_array()` must produce thirteen values. Final grammar,
borrow/result ABI and effect contracts require their separately scoped decisions
and qualification. All agreed features precede the first release unless the user
explicitly changes scope. 27-D freezes the improved source for final convergence;
28 qualifies release.
