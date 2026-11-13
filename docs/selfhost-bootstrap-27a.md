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
The unchanged original C0 ELF SHA-256 is
`e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b`.

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
seconds before the next freeze. The complete graph was then frozen at
`52ff35dd4e58194e91c239a73879daf06c3c46db` (tree
`f37277189c9b94f7955b3902efea86af1f16ca05`) as `seed3`.
Unchanged C0 built its actual O2 Stage1 in 2676.252218133 seconds:

```text
ELF SHA-256:      97e4932791657a136407c94f0f5263024e275374eed91d45e4275e2709b89416
identity SHA-256: 69b8aba495963698867bbcb08fe42e8d402f7f907a55504068933c4fb45ab75a
```

A daemon restart interrupted the outer progress monitor. The original
compile-plan process and C0 process survived with their original inputs and
7200-second timeout. Existing `accelerate.py` joined that exact running build
and authenticated the finished product. The original outer monitor has no
terminal result; its stale heartbeat is preserved. Actual completion and GNU
time come from `seed3/compile-plan-seed3`, with separate recovery/join receipts.

That corrected Stage1 passed bool/integer/float/void caught-message compilation,
independent LLVM verification, O0/O2 object/link/native exit42, strict returning
compiler/program Valgrind and invalid-input output preservation. Five recovered
type-fact corruptions and four payload-owner/coargument corruptions each made
the intended independent consumer return false and the compiler return1 with
its sentinel intact. Unchanged positive controls returned true and published
verified LLVM. These process-local negative controls change no source or ELF.

Stage1 itself compiled the identical frozen full source graph under `selfbuild1`
in 1807.085028736 seconds. Independent LLVM verification, O0/O2 optimization,
object generation, linking, ELF/symbol/relocation/machine-code inspection and
actual Stage2 execution completed successfully. The resulting products are:

| Product under `build/selfhost27a/selfbuild1/` | Bytes | SHA-256 |
| --- | ---: | --- |
| `compiler.ll` | 75,917,422 | `201faded4bf09a6509306aa73363591a8a97f5f2b5b46431d6e68311c3976a99` |
| `compiler-O0.ll` | 75,917,621 | `138df1d29e1155eb9bc774181ec50add591c7ab39de450f83ba713404db92373` |
| `compiler-O0.o` | 8,417,056 | `fed357128ec295572270be6e848aac2c367c28b40ecffa7d918b7b0422bb9e2b` |
| `astrac-stage2-O0` | 8,020,360 | `d5033b4d57b5eb322cad383fdbb67c2a64e10953c347f6cdada0a3a07d939207` |
| `compiler-O2.ll` | 21,135,272 | `56001dd9990bc2ff313c65a2597fbb3e971c9d23fd34c7750cf11d2c7b7620df` |
| `compiler-O2.o` | 2,410,408 | `eba1c9609192a17824c4d533a73495f27411b420b0757bae9dff3436f61ccb3a` |
| `astrac-stage2-O2` | 1,779,472 | `3aad388f3baa9675fbb0af24fb9268455caa103ca6771ecf3e767d7312c2ada8` |

The actual Stage1 process executable/argv and all 206 ordered source inputs
were independently observed during regeneration. Native imports contain no
process-launch entry points. The running producer's explicit environment was
captured; only the Codex helper PATH prefix changed after server recovery. All
original tool identities and the actual resolved compiler/LLVM tools remained
exact, including LLVM23.1.4. C0-to-Stage1 used 2655.50 user / 1.92 system seconds
and peaked at 2,327,584 KiB RSS. Stage1-to-LLVM used 1789.72 user / 4.43 system
seconds and peaked at 855,480 KiB RSS. These are measured costs for these exact
products. Milestone26's 9.625x/9.454x host-profile comparisons remain historical.
The raw LLVM driver route currently checks physical source correspondence
before output handling and again inside the bounded atomic writer; that
repeated verification remains part of this frozen checkpoint.

Both actual compilers passed `qualification1`: 13 independent valid-program
groups, seven invalid-program groups, 497 commands and 74 strict returning
unsuppressed Valgrind runs. Valid cases include original compiler flow-number,
builder growth, derived errors with owned buffers, fixed slices, counted C
imports, shared replacement/error cleanup, record arrays/results, caught-message
bool/numeric/void calls, distinct owned/borrowed objects, minimal arithmetic and
UTF-8 multifile calls. Both stages emitted identical raw LLVM for each of those
13 populations; O0/O2 program results matched fresh unchanged-C0 native oracles.
The direct O0/O2 object and optimized LLVM writer paths, check mode, positional
sources, source errors, alias/ownership/checked-error refusals, missing files,
duplicate/same input-output paths and returning output-write failures passed.
Failure sentinels and temporary-file discipline held. These focused current
checks complement the preserved historical 411/101/52 campaigns without
reclassifying those historical cohorts.

This establishes the first working full-source self-build. The C0 and Astra
backends produce different Stage1/Stage2 ELF bytes; small-program LLVM equality
is the measured comparison, not a final whole-compiler convergence proof.
An additional full-source Stage2-to-Stage3 cycle was not run in this bounded
checkpoint. Final improved-source convergence remains 27-D. Prepublication
preservation audit, installed publication and the separate after-delivery G7
remain required; G7 must stay PENDING inside the earlier engineering audit.

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
conditional expressions, named arguments, match expressions/nested patterns, typed interpolation,
first-class ranges and checked slicing, lazy adapters/reducers, fixed no-heap
collection, materializing comprehensions and idiomatic compiler/workload cleanup.
`(20..=80).step_by(5).collect_array()` must produce thirteen values. Final grammar,
borrow/result ABI and effect contracts require their separately scoped decisions
and qualification. All agreed features precede the first release unless the user
explicitly changes scope. 27-D freezes the improved source for final convergence;
28 qualifies release.

The later contracts still need their separately scoped decisions: range
precedence/binding and checked step/overflow behavior; result ownership and
borrow escape rules across the private/public ABI boundary; local-inference
ownership/effect rules; interpolation conversion/effect checks; and fixed
collection capacity, extent typing and materialization failure behavior. 27-A
does not finalize those grammar/ABI/effect choices or migrate source to them.
