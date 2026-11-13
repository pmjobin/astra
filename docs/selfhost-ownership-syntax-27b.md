# Ownership and syntax 27-B

This is work in progress under ASTRA-SELFHOST-27B-OWNERSHIP-AND-SYNTAX.
It does not claim implementation acceptance, Stage3 convergence or release.

The initial checkout was `e750030baa139481d89946b2b2182dbe72628d31`, tree
`8b242dffb1acd58b9a8225f466fbb5945c4d8fdd`. The original submission's 289
members exceeded the unchanged installed pm-next limit of 256. Following the
user's explicit authorization, a lossless compatible submission embeds the
entire original ZIP, preserving every original member and the original inbox
file. The replacement has 19 members and SHA-256
`6795f505907c8f19f25aee05f2677b33f6fa1d30344314507fdcee88340bc455`.
Task instructions, the Git base, installed workflow and acceptance gates are
unchanged.

The earlier user-authorized work-folder purge removed C0, the LLVM capsule and
self-build products. The complete delivered 27-A transport was authenticated:
10,006 logical files, 7,111 content blobs, 1,072,696,425 logical bytes and
24,656,244 transport bytes, SHA-256
`2167b8ac6499931bfda2d6163d3aa53c7e1525239d521ad1612544fa8bb3d222`.
The exact archived Stage1/Stage2 products and receipts were restored outside
the checkout. This grants no historical execution credit beyond those receipts.
The deleted predecessor raw-proof population was not silently reconstructed or
requalified.

The new independent after-delivery G7 is recorded separately at
`runtime/selfhost27b-g7v2/result.json`. Both actual Stage2 host profiles compiled
a fresh owner/borrow/array/loop/error/C-bridge program into native O0/O2 products.
All four executions returned 42. Six unsuppressed compiler/program Valgrind
streams had zero errors, zero live blocks and zero suppressions. Four source
negative categories preserved sentinels. Nine fresh process-local corruptions
were refused by independent consumers, and two unchanged controls passed.
The original 27-A audit's G7 remains PENDING at its original timestamp.

The user explicitly authorized continuing without original C0 or rebuilding
it. The source-preserving replacement is separately identified as
`19d744c828551b2184f06552740db1beb5b6eeb326b8e98ba56d2dfa5bca31b6`;
the historical C0 pin
`e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b`
is not relabeled. The replacement uses the unchanged bootstrap sources and
exact LLVM23.1.4 tools/library/SDK. A build-only preinclude selects GLib's
documented `g_free` function instead of the header's inferred-size macro:

```c
#include <glib.h>
#undef g_free
```

A tiny independent allocation-size-join counterexample reproduces the first
build's sized-free mismatch and confirms its removal with this setting. Both
builds and all failed/stopped harness attempts remain in runtime. The final
replacement passes the 206-file semantic-only preflight, fresh O0/O2 native
oracles, target memory checks and source negatives. Its own GLib/LLVM process
retains reachable global registries under all-kinds unsuppressed Valgrind and
therefore has **no strict process-memory PASS**. This limitation is separate
from the clean actual Astra Stage2 streams.

The replacement passed the existing public formatter campaign (405 checks over
74 sources) and the separate 66-check AST/execution/ownership/refusal pilot.
`format/toolchain.json` therefore records this explicitly requalified compiler
identity for the guarded source formatter. Historical compiler pins in prior
tests and receipts remain unchanged. Other formatter pins remain unchanged;
the exact pinned Python 3.15.0 interpreter was recovered from its archived RPM.

Before compiler edits, 451 protected paths, 6,622 donor files, 14 hooks, Git
settings, the approved E25-A-v1 proposal and the existing untracked run.py were
hash-bound in `runtime/selfhost27b-intake/pre-edit-preservation.json`.

## Explicit source semantics

The selected boundary is a single initial `language astra27b;` directive per
authored source. An absent directive means legacy semantics; an explicit
`language legacy27a;` selects the same legacy contract. The declaration must
precede namespace/import/declaration syntax. Unknown, repeated and late
directives are errors. Generated helper sources cannot select a new profile.

The parsed directive retains original source/token identities. Independent
validation rereads the source prefix before trusting the selected profile.
Ownership defaults use the declaration's own source profile, including
when a modern caller uses a legacy library signature. Raw pointers, text/slice
parameters and foreign ABI declarations retain their existing contracts.

The initial policy component is implemented and qualified at native O0 through
the authored `tests/selfhost-ownership-syntax-27b/language.py` recipe. Its actual
test ELF is `a290e55ebbe39b6a21f086350e79024a30ac132c7e6a5425818b255d80c1a583`.
It returns 42 and passes strict unsuppressed zero-live-block Valgrind. Tests
include legacy AST byte compatibility, visible modern policy, absent and forged
metadata, bad/late/repeated directives and generated-source refusal. This is a
source/syntax component witness, not a newly built production compiler or full
27-B result. Native O2 and actual next-compiler integration remain separate.

The portable recipe takes explicit `--compiler`, `--compiler-sha256`,
`--producer-kind c0|astra`, `--build`, `--runtime` and repeatable `--mode O0|O2`.
It records exact source/tool/product identities and accepts cached products only
when the full compilation identity matches. Run inside the authenticated tool
capsule; build and receipt paths must be external project work paths.

The next component receipt, `runtime/selfhost27b-syntax3/result.json`, covers
hexadecimal/binary/separated integer spelling, exact unsigned magnitude limits,
signed-minimum magnitudes, invalid prefixes/separators/suffixes, retained source
spans, lexer forks, trailing commas in calls/parameters/generics/initializers,
expression-bodied functions and both concise getter forms. The actual native
O0 component returns 42 with zero errors, live blocks and suppressions under
strict Valgrind. These tests execute the real Astra syntax implementation in a
C0-built component. They do not prove generated native programs using the new
forms. A mistaken expected literal start/end offset caused the first native
test failure; the failed execution and debugger evidence remain separate.

Integer semantic, extent/shift/bounds and both LLVM paths now decode the retained
source spelling. The independent LLVM correspondence consumer reconstructs the
magnitude separately from both emitters. Ownership default implementation covers
eligible native field/result channels and typed-local acquisition from actual
owning producers. Ordinary native parameters borrow, explicit `owned` and
`move` remain consuming, and typed aliases never acquire by type alone. Source
consumers reconstruct default field/result flags and acquisition provenance.
The whole 196+10 source graph passes C0 semantic preflight. The selected native
gates below have now executed; the complete ownership, ABI, error and physical
mutation campaign remains pending. There is no full 27-B acceptance claim.

`tests/selfhost-ownership-syntax-27b/build.py` builds the real production driver
from an immutable Git-authenticated snapshot with explicit compiler/hash/mode,
out-of-source build/runtime paths and the exact LLVM23.1.4 capsule. It runs the
fast C0 semantic preflight before a complete build and records source Git blob,
tool, dependency, provider, command and product hashes. A successful build is
explicitly reported as unqualified until its separate execution gates pass.

The syntax model now appends three typed modern node families while preserving
all 93 legacy kind codes: record expressions, conditional expressions and
compound assignments. Arena validation, rollback, typed projection, Binder
traversal, generic copying and independent generic/effect/deferred consumers
cover the added edges. The four maintained generator checks pass. The deferred
generator now emits the existing guarded control/definition layout exactly;
its exact-output check remains enabled.

Nominal concrete copyable record expressions and copyable shorthand now have
semantic and retained-Flow implementations. Independent consumers check the
nominal declaration, field identity, source order, complete/unique coverage and
readable value binding. The conditional implementation emits a condition, two
exclusive expression regions, explicit predecessor edges and a typed phi.
Independent CFG/SSA/LLVM consumers reconstruct the edge and value association.
Its current join domain is proven copyable values; owner/borrow-view joins are
still pending and receive no acceptance credit. The new syntax component
receipt is `runtime/selfhost27b-conditional2/result.json`: native O0 returns 42
and strict unsuppressed Valgrind reports zero errors and live blocks. This is
parser/component evidence, separate from production-driver feature execution.

`native.py` is the portable production-driver gate recipe, with independent C0
behavior oracles, direct compiler O0/O2 generation, C destructor/call counters,
strict compiler/target memory checks and refusal sentinels. Its selected gates
must execute successfully before receiving credit. The initial updated driver
build is frozen at commit `7a74fb0`; it does not contain subsequent AST work.
Its C0-produced O0 ELF is
`5b92a3f9fb1cb5685ff549deff5c35a14c1c1efd01dd26217b0aefacd168ca58`.
The build took 1,901.901 seconds after its 57.412-second semantic preflight.

`runtime/selfhost27b-native-initial1/result.json` records actual production-driver
execution of the initial ownership/literal/concise-syntax/view/C-pointer cases.
Eight direct O0/O2 native targets and four independent C0 behavior oracles return
42. Twelve all-kinds unsuppressed Valgrind streams (four compiler processes and
eight target processes) report zero errors, live blocks and suppressions.
Destruction counters show one destruction of the owned child; an owner factory,
implicit native fields, typed acquisition, computed getters, trailing commas,
integer extremes, borrowed array parameters and unmanaged C pointer transport
execute together. Three source refusals (overflow, borrowed consumption and
double move) preserve output sentinels. A separate post-run source-hash receipt
is explicitly timestamped after execution; the improved recipe records source
hashes before execution for subsequent campaigns. Neither original receipt is
rewritten or backdated.

Compound assignment now retains a distinct full assignment token and its exact
source-sliced underlying operator. Semantic, retained-Flow, Place, CFG and
physical consumers check the source association, exact numeric/boolean operator
domain, writability, source order and backing lifetime. The target's old value
and actual address are captured before the RHS; lowering emits one write.
Copyable record fields use the independently reconstructed leaf destination.
Mutable copied parameters receive explicitly verified entry initialization.
Computed property destinations remain explicitly refused as permitted by the
task contract. The whole compiler passes C0 semantic preflight; native O0 syntax
tests for all ten operators, Places, for steps and legacy/refusal controls pass
with strict zero-live-block Valgrind (`runtime/selfhost27b-compound1`). Actual
production-driver compound/record/conditional execution is still pending.

Owner/view conditional joins and the complete
borrowed/weak lifetime contracts still require implementation and proof.
Current-compiler native record/conditional integration also remains pending.
All seven syntax groups and ownership gates
remain required for 27-B acceptance. No broad source migration is authorized:
27-C retains named arguments, match expressions, interpolation, ranges, safe
slicing, lazy pipelines, comprehensions and idiomatic compiler/library/workload
migration. The inclusive stepped range example remains thirteen values.
27-D retains fixed improved-source Stage1/2/3 convergence; 28 retains release.

The next ownership batch implements explicit Weak handles over the unchanged
24-byte native shared lifetime block. Downgrade and weak clone retain its weak
count; upgrade uses a nonzero strong-count CAS and returns null after target
death. Weak retirement never destroys the payload. Independent LLVM consumers
check every helper edge, atomic order, operand, phi and final free. These helpers
remain absent from graphs without Weak. Unique Classes do not gain a weak block.
An SSA consumer confines upgrade results to one owner local and requires a
null-success edge to dominate subsequent use. This batch also corrects ordinary
modern `shared T` parameters to borrow while preserving legacy implicit consume.

Explicit `readonly borrowed T` stored fields have a bounded proposed lifetime
rule: they must project a readonly owning sibling of the same exact native Class
type, initialized earlier in the constructor. Field replacement and arbitrary
external parameter capture are refused. The retained typed field node, source
qualifiers and constructor ordering are checked independently. This is not a
claim of general lifetime parameter support or intrinsic `[Shared]` admission.

The full 196+10 source graph passes the replacement C0 semantic preflight after
these changes (`runtime/selfhost27b-weak-borrow-preflight2`, 61.510 seconds).
The earlier temporary-borrow checker error and reserved-name formatter refusal
remain recorded. Native weak/borrowed implementation acceptance is **pending**;
the added target programs and sentinels have not yet been executed by a compiler
built from this ownership batch. The separate syntax component previously
qualified the weak spelling and modern/legacy shared-parameter boundary with
strict unsuppressed memory checks (`runtime/selfhost27b-weak-component1`).

Conditional expressions now also retain an explicit owning join when both
branches are owning producers (or one is a source-authenticated null). Only the
selected branch executes. Each selected direct move commits on its own incoming
edge before the phi; the unselected source slot remains armed for lexical
cleanup. Source, Core ownership, CFG edges, SSA consumption and physical phi
correspondence remain independently checked. Mixed owner/alias and unproved
borrow-root joins are refused. This implementation still awaits native current
compiler qualification; it has no acceptance credit from source inspection.
The full C0 semantic preflight passed in
`runtime/selfhost27b-conditional-owner-preflight2` (62.947 seconds).

The stored-borrow syntax component is now a native/strict-memory PASS at
`runtime/selfhost27b-borrow-component2`. The first attempt failed an assertion
at line 150; the retained GDB arguments identified the exact failed expression.
The parser's readonly-modifier lookahead had excluded the new borrowed token.
The correction is explicit-profile-gated and the failed product is preserved.
The independent C0 execution oracles passed for scalar conditionals, selected
owner cleanup, weak death/upgrade and sibling-owner use. C0 does not accept the
new readonly-owned combination: that oracle uses an owned field which is never
replaced; only the modern target stores and proves the separate borrowed field.

The genuine 27-A Stage2-O2 host completed the committed `e6bb230` development
compiler build in 2544.787 seconds. Its ELF is
`5b1797c90639dba4c11a0626c1d47ccef8cd84dccdf6564d622dbc6e310a9feb`.
`runtime/selfhost27b-native-syntax1` records seven successful cases: literals,
ownership defaults, concise/trailing forms, views/C pointers, record expressions
and punning, lazy scalar conditionals, and all ten compound operators. Fourteen
native O0/O2 targets returned 42; twenty-one compiler/program strict Valgrind
streams had zero errors, live blocks and suppressions. The subsequent combined
Place case failed the independent physical contract, so this campaign has no
complete PASS and did not reach its refusal cohort.

Independent diagnostic isolation (`runtime/selfhost27b-compound-isolation1`)
found that Class-field, nested-record and indexed Places passed physical
verification; a copied scalar parameter failed. The emitter correctly records
its entry initialization, but an older global lane inventory rejected all
initial-value records for non-owning slots. The correction admits exactly a
mutable copied parameter's one record; the separate entry consumer still checks
its real parameter, alloca, single store, metadata and instruction order. Native
requalification of that correction remains pending.

The authored compiler recipe can now retain C0's **O2 optimized executable IR**
for independent verification and exact downstream reuse. It does not relabel
that dump as raw or O0 IR. The ordinary C0 and Astra producer routes remain
available, with source/tool hashes and real out-of-source outputs.

The first C0 O2 build of `1e3b7f1` stopped before LLVM generation: Core function
433 (`checked_resolve_inner`) rejected a nested temporary struct projection in
weak-type resolution. The failed frozen build is retained as
`runtime/selfhost27b-driver3`. Naming the syntax node before the indexed lookup
preserves its bounded C0 producer contract. The complete compiler now passes
C0 Core preflight (`runtime/selfhost27b-intrinsic-core-preflight1`, 76.675 seconds),
and the authored C0 build route runs that gate before expensive emission.

The next source batch adds intrinsic `[Shared]` admission using C0's existing
native-v14 six-word header: descriptor, origin, strong count, weak count,
monitor and thread identity, followed by source fields. Ordinary unique Classes
remain headerless. The Error header and E25-A-v1 transport are unchanged.
Only the existing plain Shared policy is admitted here; generic/inherited,
Monitor and other policy expansions remain excluded. Intrinsic types remain
outside the existing unique ExactHeapClass/owner-slot capability. Boxed Shared
and intrinsic ownership keep distinct layouts and helper families. The
independent source consumer re-lexes the actual `[Shared]` prefix instead of
trusting cached policy bits. Payload destruction occurs at last strong release;
weak retirement alone reclaims the object allocation after the sentinel retires.
Source, layout, helper and inventory code is implemented, but actual Astra
intrinsic qualification is still **pending**.

`tests/selfhost-ownership-syntax-27b/intrinsic.py` independently observes actual
allocations using C offsetof/static assertions and read-only count/payload
observations. Its C bridge implements no count change, ownership transfer,
destructor or source function. C0-produced O0/O2 binaries both returned 42 and
passed strict unsuppressed Valgrind (`runtime/selfhost27b-intrinsic-c0-abi1`).
They observed the 56-byte complete Session allocation, 8-byte alignment,
strong/weak offsets 16/24, payload offset 48, clone/upgrade counts 3/3,
last-strong destruction once with the weak sentinel still present, failed
expired upgrade, and final weak reclamation once. This is C0 ABI oracle evidence,
not an Astra implementation PASS. A separate C0 source probe also records its
refusal of readonly scalar fields; no change to C0 was made.

The C0 O2 production build of `4b4b711` completed in 2876.608 seconds, after
61.142-second semantic and 75.808-second Core preflights. Its ELF is
`9abaef9b94e82a6bb2a49e99936759bb3fdcd93250f5e7bff2ed6627588db368`.
This is a real C0-built development Stage1, with its full frozen source and
optimized executable IR retained in `runtime/selfhost27b-driver4` and the
matching external build directory. It is not yet the final qualified compiler.

That product's intrinsic Shared O0/O2 targets passed the same C header/count,
destruction and expiration observations as C0, with strict compiler and program
Valgrind (`runtime/selfhost27b-intrinsic-native1`). The following independent
unguarded-upgrade field negative unexpectedly compiled. The whole campaign
therefore remains failed. SSA now checks field access as well as named borrow
and move uses, requires a real null comparison and a dominating success edge,
and admits equivalent short-circuit/conditional branches. New-product native
requalification of the correction is pending.

`runtime/selfhost27b-native-weak-borrow1` passed all compound operators, copied
parameter/Class/nested-record/index Places, boxed weak death/upgrade and stored
sibling borrows: eight O0/O2 targets returned 42, twelve strict compiler/program
memory streams were clean, and twelve invalid-source sentinel cases refused.
`runtime/selfhost27b-physical-owners1` independently changed actual LLVM
instructions through the public LLVM23 C API in fresh processes. Two controls
passed; ten mutations of boxed/intrinsic counts, failed-upgrade phis, atomic
ordering, allocation extent, native calling convention and Error descriptor
field were structurally valid but refused by the physical consumer without
replacing the output sentinel. These are focused evidence, not all-gate PASS.

The combined native syntax run reached owning conditional transfer and exposed
an old parser restriction on `move` within a branch. Its earlier successful
cases and its failure are retained in `runtime/selfhost27b-native-ownership1`.
The modern prefix parser now creates the ordinary named Move node; the legacy
parser remains unchanged. The focused C0-produced syntax component passed the
new conditional-move case and strict Valgrind in
`runtime/selfhost27b-move-component1`. Owning branch native execution still
requires the next compiler product. The independent mutable parameter consumer
also now verifies actual alloca extent/alignment and initialization alignment;
an authored physical alignment mutant must qualify this correction.

The next actual Stage1-to-Stage2 build deliberately records both source
revisions: the C0-built development Stage1 above compiles the corrected current
source closure. It claims no identical-source convergence or Stage3. Every
final gate remains pending until the resulting product is independently tested.

`runtime/selfhost27b-native-generic-float1` additionally passed an implicit
owning `Vector<Item>` factory/local and f32/f64 compound operations against C0
old-form oracles: four native O0/O2 targets returned 42, six strict compiler/
program Valgrind streams were clean and six source-refusal sentinels held.
The Vector library remains byte-exact legacy source.

`runtime/selfhost27b-semantic-owners4` records fourteen fresh process-local
semantic corruptions with four matched controls on the actual C0-built
development Stage1. Independent consumers refused cleared/rebound language
selection, field/local ownership omission, a coordinated signature/result-edge
ownership omission, five recovered-call fact corruptions and four caught-message
borrow/root corruptions. Each rejecting consumer actually returned false, the
compiler returned 1 and the output sentinel survived. Controls returned true,
compiled successfully and passed separate LLVM verification. The controller
derives layouts from the exact frozen C0 Core dump and checks the actual
optimized pointer signatures and live table dimensions before writes. Two
earlier controller indexing mistakes are retained without PASS. This does not
claim a new 101/52 historical cohort or qualify later Stage2 bytes.

The further Stage1 checks preserve exact legacy meaning in seven surviving
27-A program groups: record arrays, checked record results, both caught-message
groups, distinct owned/borrowed calls, exit42 and UTF-8 multifile calls. All
seven raw LLVM hashes equal the original Stage1 and Stage2 hashes. The authored
`legacy.py` replay in `runtime/selfhost27b-legacy-stage1-1` also passed fourteen
native O0/O2 targets against fresh C0 oracles and twenty-one strict returning
memory streams. This is a selected replay, not the historical full 411 cohort.

`runtime/selfhost27b-native-borrow-negatives1` passed the extra noncopyable field
shorthand, borrow-after-move and raw-owner-adoption source sentinels, along with
the sibling-borrow controls. `runtime/selfhost27b-concise-method1` passed a
combined concise method, both concise getter forms and trailing commas at
native O0/O2 with strict memory. These checks remain tied to development Stage1.

The running corrected-source generation was independently observed through
`/proc`: the exact C0-built Astra Stage1 executable was executing its full
206-source frozen plan, with no imported process-launch function and no preload
or Valgrind options. The receipt is
`runtime/selfhost27b-stage2-current1/independent-producer-process.json`.

Portable `audit.py`, `transport.py`, `delivered.py` and `recover_c0.py` recipes
make the remaining review/publication/recovery work explicit. The C0 recovery
plan has been checked against byte-exact baseline bootstrap sources and the
actual LLVM23.1.4 tools without starting another C0 build. Transport selection
will list and hash every local generated/tool/C0 debug omission. The C0 debug
ELF alone exceeds the installed 25 MiB report limit when compressed; its exact
local product is preserved rather than presented as a smaller substituted C0.
The separate G5 recipe runs only after publication and does not rewrite the
prepublication audit. Current-source final Stage2 qualification is still
pending; no implementation acceptance follows from these recipes alone.

The first corrected-source Stage1-to-Stage2 attempt stopped before LLVM with
`astrac: SSA verification failed`, exit 1 after 1087.271 seconds. It is preserved
in `runtime/selfhost27b-stage2-current1`, with its immutable source snapshot,
actual producer witness, successful C0 semantic preflight and failed execution
receipt. No Stage2 product or G3 PASS is claimed for that attempt. A separate
read-only GDB diagnosis is observing the same frozen graph's real SSA verifier
return and work-budget retirement. It changes no source, primitive fact,
verification result or limit. Final qualification and publication remain
pending while this ordinary integration failure is investigated.

`runtime/selfhost27b-dominance-component1` executes byte-exact extracted
production `RecoverBlock`, `RecoverWork` and dominance functions. Six graphs
are checked against an independently computed predecessor-set fixed point,
including diamonds, nested loops and unreachable blocks. A 100,000-block chain
leaves 7,300,000 of the unchanged 8,000,000 work budget; low-budget and invalid
successor cases refuse. C0 and Astra each produced native O0/O2 binaries with
identical observations, and both O2 binaries passed strict unsuppressed
Valgrind. This is a focused algorithm component, not a full-graph diagnosis or
successful Stage2. The continuing full-graph diagnosis has a read-only hardware
watchpoint on the local work object's exhaustion flag; the same inferior was
resumed without altering any compiler facts, results or limits.

The reserved 27-C range example remains
`(20..=80).step_by(5).collect_array()`, with exactly thirteen values. Named
arguments, match expressions, typed interpolation, safe slicing, lazy pipelines,
comprehensions and complete idiomatic compiler/library/workload migration all
remain reserved for 27-C. The fixed improved-source Stage1/2/3 convergence is
27-D, and the first release is 28.

The completed read-only diagnosis (`runtime/selfhost27b-ssa-diagnosis1`)
observed 338,396 Core nodes and 449,141 blocks. The real exhaustion flag changed
with zero remaining work inside `recover_ssa_slots`; SSA returned false and the
inferior returned 1. The debugger controller's own exit 0 is not a compiler PASS.
No primitive fact, result or work limit was overridden.

The focused correction reuses already required scans. Weak-upgrade checks run
inside the existing Core-node scan. The reverse physical block scan fills the
owner index using independently reconstructed function counts; decrementing
those counts gives the same per-function order as the standalone forward
builder, including interleaved functions. The forward use scan builds the
unchanged owner-event shortcuts. The same packed owner-state checks and
independent owner verification still execute; standalone owner-slot consumers
still reconstruct their own complete index. This removes one full Core scan
and one full block scan, about 787,537 redundant work units on the failed graph,
without changing the 8M limit or accepting producer liveness certificates.
The complete current C0 Core preflight passed in 75.707 seconds
(`runtime/selfhost27b-ssa-fused-preflight1`). A new C0-built production host and
actual Stage2/native/mutation requalification remain required.

The production Stage1 rebuild of this coherent correction is recorded in
`runtime/selfhost27b-driver5`; its semantic and Core preflights passed in
59.150 and 75.445 seconds. The smaller real-production SSA component in
`runtime/selfhost27b-ssa-component1` passed its separate C0 Core preflight in
61.678 seconds and is compiling independently through development Stage1.
It contains the actual current source/parser/semantic/Core/CFG/SSA modules and
will test the exact frozen full compiler input graph under the same 8M limit.
It omits LLVM and the production CLI and receives no Stage2/compiler credit.
Both actual products are still pending at this entry's timestamp.

The conditional fixtures now execute both selected branches. Their independent
old-form C0 oracles passed in
`runtime/selfhost27b-conditional-both-oracles1`, including four destructor
events with the expected values after two opposite owner selections. Modern
native execution remains tied to the next actual compiler qualification.

The optimized SSA-fusion development seed completed from `07fd55a` with ELF
`0b68c5459fc7ef022e72c93fb811071cf80de18f22797eba2813de75a80f10fe`
(`runtime/selfhost27b-driver5`). It remains a separately dated generation seed.
The final audit requires both a current-source C0-built host and an actual
Astra-produced Stage2 to qualify all eighteen feature groups, intrinsic ABI,
physical refusals and strict memory, plus their selected legacy replays.
The Stage2 generation seed is recorded separately from those qualified products;
no identical-generation convergence or Stage3 follows from this arrangement.

Additional development checks passed for strict f32 signed zero/f64 NaN
compound operations (`runtime/selfhost27b-compound-ieee1`), a real non-null C
static pointer retained as unmanaged native result/stored field
(`runtime/selfhost27b-raw-static-field1`), and an implicit owning array result
with typed local acquisition (`runtime/selfhost27b-array-result1`). Each has
fresh C0 old-form behavior, actual native O0/O2 and clean strict memory.

The partial-population probe first exposed C0's genuine refusal of throwing
constructors and unchecked direct null adoption into an owned field. Those
failed sources remain in `runtime/selfhost27b-partial-field1/2`. The existing
function/method error channel and an owned empty-result factory preserve that
ABI boundary. The next probe then exposed a Core provenance gap: both modern
and explicit legacy all-null Class factories were rejected despite C0 accepting
them (`runtime/selfhost27b-null-isolation1`). Read-only table observations
confirmed correct typed nulls and owner-use relations. The older heap-witness
rule required an allocation somewhere in every Class-result function.

The correction independently proves that every return is a source-verified
null of the exact declared Class type, with at least one actual return. Only
that all-absent case can omit the heap witness; every other Class result retains
the existing heap provenance and owner checks. No ABI, pointer-adoption or
resource limit changes. Complete C0 Core preflight passed in 83.949 seconds
(`runtime/selfhost27b-absence-core-preflight1`). Final native requalification of
the correction and partial field population remains pending.

The focused SSA component's first wrapper was refused at Flow after its C0
Core preflight. Its revised zero-argument entry reuses the already qualified
production OS argument transport only; loading and all compiler passes remain
Astra source. `runtime/selfhost27b-ssa-component2` built that real component in
2070.340 seconds and is checking its frozen full compiler graph. Its snapshots
predate the separate absence fix; those old bytes and live-source divergence
remain explicit and receive no final current-source compiler credit.

A probe of C0 O0 dump mode confirmed it omits the executable entry; it is not
called an executable IR product. The final current-source C0 O0 host uses the
existing ordinary native build route, while the optimized development seed can
generate the same corrected source as Stage2. The unoptimized corruption route
is bound to the real C0 build receipt, Core-map output and ELF64 x86-64 ABI, with
fresh live table checks and positive controls; it does not invent retained O0 IR.
