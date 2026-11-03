# Native ABI and qualified source formatting

NATIVEABI-13-R1 implements a bounded x86-64 GNU/Linux LLVM 22.1.8 profile.
Its final source-bound acceptance, exact HEAD/tree, per-file formatting map,
artifacts and measured costs are carried by the installed native report.
This document describes the contract; it does not claim Stage 1, a complete
self-hosting compiler, every admitted program, or another target.

## Source and physical authority

Checked source, ownership flow, independently verified Core/CFG/SSA, a copied
native/C ABI plan, read-only LLVM correspondence checks and LLVM verification
remain separate. `compiler/backend/llvm/abi.astra` records semantic type IDs,
field identities/offsets, channel order/ownership, linkage, calling convention,
result representation and source spans. LLVM layout measurements are checked
against the source-derived plan. Module-owned type/layout caches are never
queried after their owner closes. Failed verification preserves destinations.

| Boundary | Qualified representation |
|---|---|
| Private native functions | Existing `astra.fN` convention, direct LLVM record/buffer values, authoritative addresses for borrowed records |
| Application entry | Qualified `int main()` C entry |
| Explicit C imports/exports | I32, F32, F64, opaque `void*`, void results; separately checked declarations and C-callable forwarding wrappers |
| Receivers/hidden results | Absent in this bounded profile, explicitly recorded as absent |

Private aggregate transport is distinct from C0's flattened native module ABI
and from C aggregate ABI. Actual GCC/Clang translation units exercise C calls
both ways, mixed register classes, pointer identity, source-literal bits,
signed zero, subnormals, infinities and quiet-NaN payload transport. Colliding
physical C symbols and unresolved links have explicit refusal controls.
Imported borrowed-noescape pointers remain trusted foreign assertions; they
grant no LLVM capture, purity, alias, alignment or validity attributes.

## Floating values and ownership

The emitter uses real LLVM float/double, strict operations and comparisons,
signed-zero negation and explicit width conversions. Integer-to-floating casts
round directly to the destination format. Floating-to-integer casts implement
the documented truncation-first intervals, rejecting nonfinite/out-of-range
inputs before conversion and sanitizing speculative operands. An independent
checker reconstructs those intervals from source widths; a separate physical
guard corruption is rejected without relying on a hash seal.

Nested record fields retain their original place/field authority and measured
padding/alignment. Buffer replacement completes the RHS before retiring the
old owner, then disarms/stores/rearms the exact location. Ordinary exits, loop
paths, distinct owners, empty replacement and failed allocation have explicit
trace controls. Self-move replacement and owning-record reassignment rejected
by the unchanged C0 reference remain rejected. Fatal SIGILL tests are separate
from normal lifetime assertions. Volatile owner storage and allocator call
markers remain where required to preserve observable retirement under O2.

## Formatting contract and evidence

The user's original and edited model guided formatter version 2. Restricted
single-statement if/for/while bodies have the same scoped Block AST in both
frontends, under the separately recorded owner approval. Declarations, nested
controls and bound else bodies retain braces. Unsupported Astra else-if,
do/finally and labeled-loop spellings retain parser refusals; supported Vala
exception/do forms have their own token and execution pilots.

The single broad mechanical commit is
`7e63276e091069644dd8a042792ccb7f3f11e6fd`, tree
`b2cfd26bb38d651b6a8bb656a585d21d2dc9b2fe`.
Its guarded pass classified 4,638 sources and changed 3,033, deleting 6,143
parser-approved brace pairs and recording 21,192 added/12 removed blank lines.
The independent AST/token checks preceded all writes; a clean check and actual
second apply both reported zero changes before that commit.

All original 446 protected files remain byte/mode exact. Five additional true
proof/debug inputs were identified before the pass, giving 451 protections.
C/C++ scope braces and call/declaration interiors remain byte-exact because
macro stringification can observe argument whitespace. The actual JavaScript
units retain restricted line-terminator boundaries. Vala scope braces remain
where removal has no independent lifetime proof; its token and execution pilots
preserve supported exception/do forms. Source diagnostics/debug
coordinates are checked against actual inputs, including GDB/DWARF and native
module/foreign-frame controls. The maintained numeric-unit debugger harness
derives its current statement line rather than freezing an example's layout.

One native-scope validation helper was added after the mechanical commit, in a
separate functional commit. The final full check covers 4,639 classified files.
The report map preserves the mechanical hashes and separately identifies later
functional changes/new compliant code. The fresh formatter binary is
SHA-256 `908f8db9e524cf94b7651f36e9bf0ff32c98ef64cb7eacd737c3b5f680064b45`;
its source/build inputs, 405 public checks, expanded pilot and 66 exact paired
compiler observations are retained. The unchanged independent C0 reference is
SHA-256 `30865ad8a9d1652b63ad882f1e29031c76ac13204212f822b44235cb07df10de`.

## Qualification boundary

The selected corpus is 39 distinct sources at each profile: every original 24,
14 additions (four FP, six C, four aggregate/memory), and the unchanged inherited
`existing-nested` f64 record. Additional numeric, C-channel, owner and formatted
scope controls do not inflate that selection. The closure retains original21
LLVM faults, new17 ABI/lifetime faults plus one numeric-guard fault, Core22,
CFG26, SSA30, all original80 statuses and the original1044 observations.
The historical existing-nested deferral remains historical; current verified
IR coverage can include all56 positives without claiming all56 executed.

Valgrind numerical conformance has one explicit instrumentation deferral.
Native Astra/C0 and independent GCC/Clang executables produce f32 bits
`5f000001` for u64 9223372586610589697; the installed Valgrind produces
`5f000000` for both C reproducers, including with VEX optimization disabled.
The corresponding instrumented numeric check exits1 and is recorded as
deferred, never as numerical PASS. Native expectations stay exact. All observed
memory errors/lost bytes remain zero, and the selected39 programs and owner
traces pass unsuppressed Valgrind. This does not qualify arbitrary emulated FP.

General/typed foreign pointers, C aggregate-by-value, C ownership transfer,
callbacks/variadics/retention, broader exception/async/generic semantics,
Windows execution and other targets remain outside this profile. The focused
affected closure replaces no historical registry. API token/dollar charges are
not available to this session; actual build/test/formatter costs and retries
are recorded separately, including overlapping wall intervals and warm reuse.

Final native build measurements are 647.55s wall/641.53s CPU and 1,475,556 KiB
maximum RSS at O0, and 1129.04s wall/1118.67s CPU and 1,526,148 KiB at O2.
Exact-product warm checks take 1.03s/1.09s. The broad formatter apply takes
289.44s; the pre-commit clean check/zero reapply take 291.17s/293.52s. These are
actual runs with concurrent build work, not a matched performance comparison.

Both final profiles pass the complete focused closure. Before/after pairing
checks all39 source-bound ABI plans, raw/optimized IR, objects, executables,
memory observations and independent mutation receipts byte-exact. Six rebuilt
query products reproduce all1044 original observations with their original
input bytes and exits. Final format check: all4639 classified files, zero
changes; protected451 and donor6622 identities remain exact. The installed
publisher's `RESULT.json`/`MANIFEST.json` supply the final publication identity.

The installed publisher limits the final ZIP to 25 MiB. All native components,
selected program artifacts, full patches, formatting maps and raw receipts are
included losslessly. The three existing C0 tool binaries remain local; the
report carries their exact hashes, source identities and rebuild/qualification
receipts rather than distributing these tools.

The owner approved base `b589e48ec94131de3b330f6377076ddbdac88c62`, whose tree is
the required `46f72a3381161aac36f158c5b5a5ccd0d551e9af`, after the earlier email
history rewrite. The original R1 ZIP remains byte-exact; the unchanged installed
intake accepted the separately identified approved-base derivative. No history
rewrite, push, installation, donor mutation or release is part of this task.

Made by Ria and Pim. 💙🖤
