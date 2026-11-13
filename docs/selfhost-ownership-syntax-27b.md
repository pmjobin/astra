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
