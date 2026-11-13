# Ownership and syntax 27-B

## Verdict and scope

The bounded 27-B ownership contract and all seven syntax groups are implemented
and qualified through current-source C0-built O0 and actual Astra-built O2
compilers. Each host generated actual native O0/O2 targets. The overall report
is **PARTIAL** because earlier user-authorized cleanup deleted the original C0
and historical raw proof population. Replacement C0 is separately qualified and
identified; absent historical bytes are never claimed preserved or re-executed.
This is a separate next submission after 27-A, with no Stage3 or release claim.

The final prepublication audit is produced by
`tests/selfhost-ownership-syntax-27b/audit.py`. G5 remains PENDING in that audit;
`delivered.py` performs the separately dated check only after installed
publication. A successful build alone never grants qualification.

## Intake, recovery and new 27-A G7

Initial HEAD: `e750030baa139481d89946b2b2182dbe72628d31`.
Initial tree: `8b242dffb1acd58b9a8225f466fbb5945c4d8fdd`.
Original submission SHA-256:
`67f26affa538914e1665528c3175d10e9b5aab735c65a42510d70c4e4dc7e7eb`.

All original 289 members were authenticated, but exceeded the unchanged
installed pm-next cap of 256. Explicitly authorized lossless compatible
packaging embeds that exact ZIP and preserves its task and Git base:
19 members, SHA-256
`6795f505907c8f19f25aee05f2677b33f6fa1d30344314507fdcee88340bc455`.
The original inbox file and installed workflow remain unchanged. Publication
uses ordinary next mode, without amendment of 27-A.

Exact predecessor: 24,811,599 bytes, SHA-256
`de5cd9ed28c3960c272bf9456cbdbb2127d3fd17ee3cb0e867e320fbe6ae2a7d`.
Its 45 indexed members, 20 source Git blobs and 15 transport segments were
verified. The 24,656,244-byte transport reconstructs 10,006 logical files,
7,111 blobs and 1,072,696,425 logical bytes, SHA-256
`2167b8ac6499931bfda2d6163d3aa53c7e1525239d521ad1612544fa8bb3d222`.
Deleted first-selfbuild products and frozen source snapshots were recovered
only outside this checkout. Historical references were never source replacements.

**New independent after-delivery 27-A G7 passed before source edits**, separately
dated in `runtime/selfhost27b-g7v2/result.json`. Both actual old Stage2 hosts
compiled fresh owner/borrow/array/loop/error/C-bridge programs: four native
O0/O2 returns of 42, six strict unsuppressed memory streams, four source-negative
categories, and nine independent fact corruptions with two positive controls.
The original 27-A audit still records G7 PENDING at its original timestamp.

The user authorized proceeding without original C0 or rebuilding it. The
replacement SHA-256 is
`19d744c828551b2184f06552740db1beb5b6eeb326b8e98ba56d2dfa5bca31b6`;
the deleted original
`e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b`
is not relabeled. Unchanged bootstrap sources use exact LLVM23.1.4 tools,
library and SDK. A build-only preinclude selects GLib's existing `g_free`
function instead of its inferred-size macro:

```c
#include <glib.h>
#undef g_free
```

A retained allocation-size-join counterexample demonstrates the original
sized-free mismatch and its removal. C0 passes full source semantic/Core
preflights, old-form native oracles, target memory and source negatives.
Its own GLib/LLVM process retains reachable global registries under all-kinds
Valgrind and has **no strict process-memory PASS**. Formatter qualification
passed 405 checks over 74 sources and the separate 66-check pilot; the explicit
replacement pin is recorded in `format/toolchain.json`. Other formatter pins
and the installed six workflow files are unchanged. `recover_c0.py` records the
portable source-preserving recovery recipe.

## Implemented language contract

A single initial `language astra27b;` selects modern semantics. Absence or
explicit `language legacy27a;` preserves legacy defaults. Unknown, late,
repeated and generated-source directives refuse. Independent consumers re-lex
the original prefix; declaration-source policy governs cross-profile calls.
Compiler/library implementation sources retain C0-accepted legacy spelling.

Eligible native stored fields and owning results default to ownership. Typed
locals acquire only from actual owning producers, equivalently to `var`;
ownership is never inferred from alias type alone. Ordinary modern native
parameters borrow; explicit `owned` and `move` consume/transfer. Legacy implicit
consuming Shared parameters retain their meaning. Strings, views, raw pointers
and foreign ABI channels retain their existing contracts.

A `readonly borrowed T` field must bind an earlier initialized readonly owning
sibling of the same exact native Class type. External capture, replacement,
wrong ordering and use after movement refuse. Borrowed-field use is confined
to the proved receiver and temporary borrowed calls; new local aliases without
a supported source-root proof refuse. General lifetime parameter/alias admission
is not claimed. Failed alias probes remain separate evidence.

Weak observers support boxed Shared and plain intrinsic `[Shared]` lifetimes.
Boxed blocks remain 24 bytes. Intrinsic native-v14 headers retain descriptor,
origin, strong, weak, monitor and thread words; payload begins at byte 48.
Unique Classes remain headerless. Error layout and E25-A-v1 remain unchanged.
Upgrade requires nonzero strong-count CAS and a dominating non-null check;
expired targets cannot resurrect. Last strong release destroys payload; final
weak retirement frees storage. Generic/inherited intrinsic and Monitor-policy
expansion remain outside the eligible set.

All seven syntax groups have real native qualification:

- Compound assignments: all ten supported operators, exact types, one checked
  Place/old-value evaluation before RHS, one write, nested record/Class/index
  and copied-parameter destinations. A RHS mutates the same array element and
  the final value proves the old load preceded that mutation. Throwing RHS
  performs no final write. Computed property destinations remain excluded.
- Hexadecimal, binary and separated integer literals: exact widths, unsigned
  extremes, signed minima, retained spans and malformed/overflow refusals.
- Trailing commas in supported calls, parameters, generics and initializers.
- Concrete copyable nominal records: nested construction, direct call arguments,
  complete unique fields and reverse-written field evaluation order.
- Expression-bodied functions/methods/getters, including conditional getters
  and a concise owning factory with the existing checked error channel.
- Copyable named-field shorthand; noncopyable owner punning refuses.
- Lazy right-associative `?:`: copyable and proven owning joins, both move
  selections, fresh allocations and absence versus allocation. Unselected moves
  remain armed. Mixed owner/alias and unproved borrowed-view joins refuse.

The model appends three typed node families after all 93 legacy codes.
Maintained generators and source/Core/CFG/SSA/LLVM consumers cover their edges.
Record-call admission requires independent nominal/source/field proof; constructor
conditionals check both branches at the same proved initialization point.

## Products and actual qualification

`build.py` freezes committed 196 compiler sources, ten libraries and seven C
providers, runs fast semantic/Core admission, and hashes inputs, tools,
dependencies, commands, timings and products. Builds stay out of source.
C0 O2 retained IR is an optimized executable dump; C0 O0 dump mode omits its
entry and is not presented as executable IR.

| Role | Frozen revision | ELF SHA-256 |
|---|---|---|
| Optimized C0-built development seed | `eef1b2cc319d84c10e21d702101e6b30e21543c8` | `593ad393bd9384a27176fc9bcde33d507ea77a7d8516488e98961aed115f813d` |
| Qualified current C0-built O0 Stage1 | `fdcadeb5dfa3f7a44c64109c1790e67b3b81d828` | `d749bb6ba5bcc2922bf5ec315bae9ccd5359914ad94644fd351358c1927bc074` |
| Qualified actual Astra-built O2 Stage2 | `7ef012447fcfdf9052248abf11b91b5c873180b1` | `cdec4cea1ce00a14640eb1ad2dde93ee71c88155e69028c7c5e081f993f05d92` |

Current Stage1/Stage2 snapshots contain identical compiler/library/provider
source bytes despite different full Git revisions. Actual Stage2 producer is
the separately versioned optimized seed, which predates the final record-call
and constructor-conditional source checks. Its immutable Git snapshots remain
bound separately. Live `/proc` observation authenticates the actual executable,
206-input argv, environment and non-delegating imports. No same-generation byte
convergence or Stage3 follows from this arrangement.

The optimized seed build took 2842.277 seconds; current C0 O0 build took
2143.096 seconds; actual current-source Astra build took 2594.646 seconds.
Full receipts retain wall/user/system time, RSS and all failed/stopped attempts.

Both final hosts passed:

- `native.py`: eighteen cases, 36 native O0/O2 targets per host, matched explicit
  C0 oracles, 21 source refusal categories/sentinels, and 54 strict compiler/target
  returning memory streams per host. Cases include CRC32, generic/array owning
  results, stored weak/borrowed fields and exceptional/nonempty field replacement.
- `intrinsic.py`: actual linked C layout/count/destructor/free observations,
  implicit strong stored field, expiry and unguarded-upgrade rejection; five
  strict memory streams per host. C observers implement no ownership feature.
- `physical.py`: fourteen actual LLVM-valid corruptions refused at independent
  consumers, with six controls per host; calling convention, atomic/count/phi,
  allocation, Place address, copied-parameter store and record-frame checks.
- `legacy.py`: seven surviving exact 27-A groups, fourteen native targets and
  21 strict memory streams per host; every raw LLVM identity equals the original
  Stage1/Stage2 identity. This is not a complete 411-program replay.

`semantic.py` additionally passed fourteen source/profile/field/local/result/
call/borrow corruptions and four controls on the current C0-built host. The O0
route binds its actual build receipt, Core-map output, ELF64 ABI and live shapes
without inventing retained O0 IR. Total final returning memory streams: **160**,
zero errors, zero live blocks and zero suppressions under the explicit strict
all-kinds options.

## Retained failures and independent boundaries

Material retained failures include readonly/borrow parser lookahead, a
C0-incompatible temporary nested projection, copied parameter initialization,
weak field guards, pure-null Class provenance, conditional heap provenance,
record arguments, and preferred versus ABI stack alignment. C0 rejects throwing
constructors and direct unchecked null adoption into owned fields; the tests
use existing method/error and owned empty-result channels.

The first Stage2 attempt exhausted the unchanged SSA8M budget. Read-only GDB
observed real exhaustion; controller exit zero was never compiler success.
Scan fusion reuses existing Core/reverse-block/forward-use scans while keeping
reconstructed owner indices and packed independent checks. Generic256 and SSA8M
limits are unchanged. The real SSA component passed its frozen graph in
968.280 seconds, then correctly failed its separate live-source stability
assertion after the absence fix; the disclosed frozen success grants no final
current-source compiler credit.

The next full build failed physical checking. A tiny actual module passed LLVM
structural verification; exact LLVM23.1.4 independently reported ABI alignment 4,
preferred alignment 8 and actual record alloca alignment 8. The consumer now
requires preferred allocation alignment and ABI store alignment, preserving
emitted bytes. Final controls and LLVM-valid alignment mutations both qualify it.

## Preservation, publication and reserved milestones

The audit checks all 451 protected paths, 6,622 donor files, fourteen hooks,
Git settings, 5,291 original scope entries, five excluded Windows scripts,
existing untracked user work, first-selfbuild products and exact predecessor.
Approved proposal SHA-256 remains
`d77c02f3144ab5dc3da41eb310b29cd02629b49876042934ea5071a1549ac66e`.
Historical 411 identities/profile, 101/52 mutations/profile and R4/R5
qualifications/limitations remain historical. The purged raw 1,044-proof
population is not claimed preserved or re-executed. This prevents overall PASS.

`transport.py` hashes every explicit local omission: redundant predecessor
transport, external tool distributions, scratch and oversized C0 debug products.
Actual 27-B compilers, current snapshots, native products, receipts and failed
attempts are transported. Oversized recovery C0 debug bytes remain local with
hashes and rebuild commands; no substituted C0 binary is presented.
Only unchanged installed pm-next publishes the canonical next report.
`delivered.py` independently checks exact ZIP/source/transport identity and fresh
live Stage2 O0/O2 CRC, C ABI, strict memory and physical negatives after delivery.
Prepublication G5 remains PENDING.

27-C retains complete idiomatic compiler/library/workload migration, named
arguments, match expressions/nested patterns, typed interpolation, ranges,
safe slicing, lazy pipelines/reducers and comprehensions. The fixed example
`(20..=80).step_by(5).collect_array()` has thirteen values. 27-D retains fixed
improved-source full Stage1/2/3 convergence. 28 is the first release. None is
dropped or claimed by 27-B.
