# Ownership and syntax 27-B

## Current qualification state

ASTRA-SELFHOST-27B-OWNERSHIP-AND-SYNTAX is a separate submission after 27-A.
The bounded implementation is committed. Final current-source compiler builds
and their complete qualification are **pending**; there is no implementation,
Stage3, convergence or release PASS from this document.

Initial HEAD was `e750030baa139481d89946b2b2182dbe72628d31`, tree
`8b242dffb1acd58b9a8225f466fbb5945c4d8fdd`. Original submission SHA-256:
`67f26affa538914e1665528c3175d10e9b5aab735c65a42510d70c4e4dc7e7eb`.
Its 289 members exceeded the unchanged installed pm-next limit of 256.
Following explicit user authorization, lossless compatible packaging embeds the
exact original ZIP, preserves the task and Git base, and passes native intake:
19 members, SHA-256
`6795f505907c8f19f25aee05f2677b33f6fa1d30344314507fdcee88340bc455`.
The original inbox ZIP and installed workflow remain unchanged. This is an
ordinary next publication, without amendment of 27-A.

## Recovery and independent entry gate

The exact predecessor report is 24,811,599 bytes, SHA-256
`de5cd9ed28c3960c272bf9456cbdbb2127d3fd17ee3cb0e867e320fbe6ae2a7d`.
Its 45 indexed members, 20 source Git blobs and 15 transport pieces were checked.
The reconstructed transport is 24,656,244 bytes, SHA-256
`2167b8ac6499931bfda2d6163d3aa53c7e1525239d521ad1612544fa8bb3d222`:
10,006 logical files, 7,111 blobs and 1,072,696,425 logical bytes. Deleted
first-selfbuild products and their frozen sources were restored only outside
this checkout. Historical reference contents were never source replacements.

The earlier user-authorized work-folder purge also deleted original C0 and the
raw historical proof population. The user authorized proceeding without C0 or
rebuilding it. Replacement C0 is separately identified as
`19d744c828551b2184f06552740db1beb5b6eeb326b8e98ba56d2dfa5bca31b6`;
the original pin
`e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b`
is not relabeled. Unchanged bootstrap sources were rebuilt with the exact
LLVM23.1.4 tool/library/SDK capsule. A build-only preinclude selects the existing
GLib `g_free` function instead of its inferred-size macro:

```c
#include <glib.h>
#undef g_free
```

A separately retained allocation-size-join counterexample demonstrates the
initial sized-free mismatch and its removal. Rebuilt C0 passes full semantic
and Core preflights, native O0/O2 oracles, target memory and source negatives.
Its GLib/LLVM process retains reachable global registries under all-kinds
Valgrind and has **no strict process-memory PASS**. The public formatter's
405 checks over 74 sources and its separate 66-check pilot passed; only the
explicitly requalified compiler identity changed in `format/toolchain.json`.
The portable recovery recipe is `tests/selfhost-ownership-syntax-27b/recover_c0.py`.

**New after-delivery 27-A G7 passed before source edits**, separately dated in
`runtime/selfhost27b-g7v2/result.json`. Both actual old Stage2 hosts generated
fresh O0/O2 native owner/borrow/array/loop/error/C-bridge programs: four returns
of 42, six strict unsuppressed compiler/program memory streams, four source
negative categories and nine independent fact mutations with two controls.
The original 27-A engineering audit still records G7 PENDING at its original
timestamp. This new check never rewrites that historical audit.

## Implemented contract

A single initial `language astra27b;` selects the new source semantics.
Absence or explicit `language legacy27a;` preserves legacy defaults. Unknown,
late, repeated and generated-source directives refuse. Independent consumers
re-lex source and authenticate the retained profile; declaration-source policy
also governs calls across profiles. Compiler/library sources remain in the
C0-accepted legacy spelling; broad migration is reserved for 27-C.

Eligible native stored fields and owning results default to ownership. Typed
locals acquire only from actual owning producers, equivalently to `var`;
typed aliases do not acquire by type alone. Ordinary modern native parameters
borrow; explicit `owned` parameters and `move` transfer ownership. Legacy
implicit consuming Shared parameters retain their old meaning. Strings,
views, unmanaged/raw pointers and foreign ABI channels keep their contracts.

Explicit `readonly borrowed T` fields have a bounded lifetime rule: an earlier
constructor initialization must bind the same exact native Class through a
readonly owning sibling. External capture, replacement and use after movement
refuse. This does not introduce general lifetime parameters.

Weak observers support existing boxed Shared lifetimes and plain intrinsic
`[Shared]` Classes. Boxed control blocks remain 24 bytes. Intrinsic native-v14
headers retain descriptor/origin/strong/weak/monitor/thread words and the payload
after byte 48. Unique Classes stay headerless; Error layout and E25-A-v1 stay
unchanged. Upgrade requires a nonzero strong-count CAS, cannot resurrect an
expired object, and its result needs a dominating non-null success check.
Last strong release destroys the payload; final weak retirement frees storage.
Generic/inherited intrinsic and Monitor-policy expansion are excluded.

All seven syntax groups are implemented through parser, semantics, effects,
ownership, retained IR and physical correspondence:

- Compound assignment: all ten operators, exact types, checked writable Places,
  one address/old-value evaluation before the RHS and one write. Nested record,
  Class, index and copied-parameter Places are covered; computed properties
  remain refused. f32 signed zero and f64 NaN retain strict behavior.
- Hexadecimal, binary and separated integer literals: retained spelling,
  independently decoded exact widths, signed minima and overflow refusals.
- Trailing commas in calls, parameters, generic lists and initializers.
- Concrete nominal copyable record expressions with complete unique fields.
- Expression-bodied functions, methods and both concise getter forms.
- Copyable named-field shorthand; noncopyable owner punning refuses.
- Lazy right-associative `?:`, including copyable joins and proven owning joins.
  A selected direct move commits on its incoming edge; the other source remains
  armed. Mixed owner/alias and unproved borrowed-view joins refuse.

The syntax model appends record/conditional/compound kinds after all 93 legacy
codes. Maintained generators, source consumers, Core/CFG/SSA and LLVM physical
consumers cover their typed edges. Ownership helper bytes, atomic ordering,
call conventions, Place stores and phi associations are independently checked.

## Production integration and retained failures

`build.py` freezes committed 196 compiler and 10 library inputs plus seven C
providers, hashes tools/dependencies, runs fast semantic/Core preflights and
builds out of source. A build receipt explicitly grants no feature acceptance.
C0 O2 retained IR is identified as an optimized executable dump; C0 O0 dump
mode omits the executable entry and is not presented as executable IR.

The optimized development seed from `07fd55a` is
`0b68c5459fc7ef022e72c93fb811071cf80de18f22797eba2813de75a80f10fe`
(`runtime/selfhost27b-driver5`), built in 2909.148 seconds. Final current C0 O0
Stage1 and actual Astra O2 Stage2 builds froze the same corrected `83c23e1`
source. The actual Stage2 producer is this separately identified development
seed, not the parallel current C0 product. A live `/proc` witness binds its
executable and full 206-input argv and checks non-delegating dynamic imports.
No same-generation convergence follows from this arrangement.

All failed/stopped probes remain separate. Material fixes include copied
parameter entry-store admission/alignment, weak upgrade field guards, parser
lookahead for readonly borrowed fields, and a C0-incompatible temporary nested
projection replaced by a named syntax node. C0 rejects throwing constructors
and unchecked direct null adoption into owned fields; the partial-population
fixture uses its existing method/error channel and an owned empty-result
factory. A Core correction admits only a nonempty set of source-verified null
returns of the exact declared Class type without a heap allocation witness.
All other Class results retain heap provenance and owner checks.

The first final Stage2 attempt failed SSA after 1087.271 seconds. Read-only GDB
observed the real 8M work exhaustion inside `recover_ssa_slots`; controller exit
zero was not treated as compiler success. Scan fusion reuses existing Core,
reverse-block and forward-use scans while retaining reconstructed owner indices
and independent packed owner checks. Generic256 and SSA8M limits did not change.
A byte-exact production dominance component passed independent graph oracles
and a 100,000-block chain. The real SSA component then returned
`CURRENT_PRODUCTION_SSA_VERIFIED_8M 338527 449389` in 968.280 seconds. Its outer
controller correctly rejected later live-source divergence from the separate
Core absence fix. `frozen-qualification.json` records the real frozen success
and that failure without granting final current-source compiler credit.

Earlier detailed development entries remain in Git history; their original
failed receipts, sources and products remain local and selected for transport.

## Required final evidence and publication

`native.py` covers eighteen cases, independent old-form C0 behavior, direct
current compiler O0/O2 generation, source sentinels and strict unsuppressed
compiler/program Valgrind. `intrinsic.py` uses a C bridge that only observes
allocation/header/count/destructor/free behavior. `physical.py` injects fourteen
actual LLVM mutations before structural verification, with six controls.
`semantic.py` corrupts fourteen source/owner/call/borrow facts at independent
consumers, with four controls. The C0 O0 route authenticates its real build,
Core map, ELF64 calling ABI and live shapes without inventing retained O0 IR.
`legacy.py` replays seven surviving exact 27-A groups against their original
raw LLVM identities; it does not claim a full 411-program replay.

`audit.py` requires final matched-source C0 Stage1 and Astra Stage2 receipts,
both feature/ABI/physical/legacy campaigns, source fact negatives and 160 clean
returning memory streams. It also checks 451 protected paths, 6,622 donor files,
14 hooks, Git settings, the existing untracked user file, original scope entries,
first-selfbuild products, exact predecessor report and approved proposal SHA
`d77c02f3144ab5dc3da41eb310b29cd02629b49876042934ea5071a1549ac66e`.

The historical 411 identity and 101/52 mutation qualifications remain historical.
The purged raw 1,044-proof population is not claimed preserved or re-executed.
Consequently the planned overall report is **PARTIAL**, even if current bounded
implementation gates pass. `transport.py` lists hashes for every local omission,
including external tool distributions and the oversized C0 debug product;
actual 27-B compiler/native products and source snapshots are transported.
Only unchanged installed pm-next publishes the canonical report. `delivered.py`
runs separate exact-ZIP, live Stage2 native O0/O2, C ABI, strict memory and
physical-negative G5 checks after publication. Prepublication G5 stays PENDING.

## Reserved milestones

27-C retains complete idiomatic compiler/library/workload migration, named
arguments, match expressions, typed interpolation, safe slicing, lazy pipelines,
comprehensions and `(20..=80).step_by(5).collect_array()` with thirteen values.
27-D retains fixed improved-source full Stage1/2/3 convergence. 28 is the first
release. None is dropped or claimed by 27-B.

The next full-source Astra generation passed SSA but stopped at the independent
LLVM physical contract after 1485.544 seconds (`selfhost27b-stage2-current2`).
A tiny mutable record reproduced the rejection. The captured emitted module
passed independent LLVM structural verification; the exact LLVM23.1.4 C API
confirmed ABI alignment 4, preferred alignment 8 and actual alloca alignment 8.
The newly tightened checker had incorrectly required ABI alignment for both
stack allocation and stores. It now independently requires preferred alignment
for LLVMBuildAlloca and ABI alignment for its stores, preserving emitted bytes.
The physical campaign adds a record-frame alignment corruption and a matched
control. This correction requires fresh current-source production qualification.

The `83c23e1` C0 O0 development host completed in 2124.418 seconds with ELF
`bb2285248f6fa27843e86071b8790ed475f6c3b56da00edcb97be8328d57f971`.
It predates the alignment correction and is not a final qualified host.
A focused owner-conditional native probe exposed a separate Core provenance
gap: the actual heap consumer did not follow kind-77 result branches. Its
read-only debugger observation returned false; the source/owner checks were
not overridden. The walker now follows only source-proven owning result
branches, never the condition. Direct fresh constructor branches additionally
require their exact independently reconstructed conditional consumer. The
expanded fixture exercises both move selections, both fresh allocations and
absence versus allocation; its explicit old-form C0 oracle returns 42 with
seven destructions and sum 128. Final current-native proof remains required.

Focused current development checks now cover a weak observer stored in a
Watcher field and an implicit intrinsic Session strong field. Both have actual
O0/O2 native execution, explicit C0 equivalents and clean strict memory. The
final fixtures retain these field paths. Borrowed-field use remains bounded
to the proved sibling receiver and temporary borrowed call; attempts to retain
a new local alias are refused without a supported source-root proof. The
separate failed alias probes are retained and grant no acceptance credit. This
does not claim general lifetime/alias admission or infer ownership by type.
