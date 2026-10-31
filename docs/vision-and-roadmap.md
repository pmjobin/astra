# ASTRA

## Vision, Roadmap & Open Decisions

**Version 1.2 · 4 October 2026**\
**Planning reference for Pierre-Marc Jobin and Asteria**  
**Latest accepted repository delivery:** CALLABLE-1-R1, `a7cb205b6ac9b4341455f0798f4af041206de134`\
**Latest delivered source language feature:** OWN-SWAP-1, `ca7c2301c60f92185e1c8689b3d41f470ee92b0f`\
**Last complete strict-suite evidence:** CALLABLE-1-R1 historical 9,103-test run; no new suite here\
**Current housekeeping:** DOCS-SYNC-1 — submitted; acceptance pending  
**Current design checkpoint:** ASTRA-ENUM-ERROR-CONTRACT-1 — review-ready proposal; detailed approval pending. [Bounded amendment](#enum-error-contract-1).

> Make sophisticated systems programming look ordinary. Preserve meaningful cost and danger; remove redundant ceremony.

**2026-10-18 source checkpoint:** Surge 10 implements recursive owning values,
general closed containers and iteration, composed property/refinement contracts,
Unicode scalar operations, selected native descriptors and composite native
units. The current Bible/Q01–Q35 map
records finite profiles and remaining decisions; the
working ledger keeps qualification
stages separate. All twelve A73–A84 are implemented. The
final G1–G9 qualification passes 119
selected current-source suites; historical milestones and LAZY Q4 retain their statuses.
The agreed later campaigns remain numerical/optimizer policy (11), actual
non-SH-4 no-OS plus allocators (12), threads/networking (13), and native GObject
export/tooling/resolver/release (14). Self-hosting and SH-4 work are excluded.

**Surge 11 implementation checkpoint:** scoped floating policies, bounded vector
memory, public DSP modules, derived effects and finite local object/lazy/exact
dispatch/Shared optimizations now have component evidence for A85–A96. The
updated Bible/Q-register map records
their boundaries. Integrated N1–N9 qualification
passes 137 selected registrations and all twelve new applications. Later surges
and historical outcomes remain unchanged.

This document consolidates the founding vision, subsequent amendments, the source-based roadmap review and the instruction to follow that path closely. It is the working planning reference for subsequent submissions. It is not a claim that planned features exist, nor a blanket authorization to resolve every open language-design question during implementation. This Markdown is the living master. The original PDF remains the matching **v1.0 reading snapshot**; it has not been regenerated or relabeled v1.1. A reading-edition refresh is a separate artifact update. The [approved v1.0 Markdown](history/ASTRA_VISION_AND_ROADMAP_v1.0_2026-09-27.md) remains byte-for-byte historical.

The [2026-10-04 amendment](#enum-error-contract-1) supplies current delivery and
priority status; retained v1.1 present-tense baseline/planning summaries below
remain prior context where that dated amendment supersedes them.

Version 1.1 adds only documentation reconciliation and the bounded generated milestone label correction. Its focused checks are new evidence; no full strict suite, full application corpus or profiling matrix was rerun. The [current capability matrix](language/capabilities.md) links present source, applicable decisions and tests. The imported source audit remains a qualified historical snapshot, separately identified from the Git delivery. [R2] [R3] [R4] [R10] [R11]

**Native language/runtime checkpoint 2026-10-17:** Surge-4 implements bounded
explicit shared/weak lifetime and genuine typed function/owning closure values,
with eight application witnesses. Consult the current coverage
and fresh qualification for delivered subsets
and remaining gates. This source delivery does not accept historical LAZY Q4,
upgrade Surge-3's PARTIAL status, or authorize self-hosting. The next broad
campaign should address a useful remaining runtime/foreign workload, with
explicit provider/retention evidence, rather than infer Bible completion.

**Owned-state checkpoint 2026-10-17:** Surge-6 is **PARTIAL**. Exact-Class Bag
stable take/replacement and a selected checked-admission byte arena are implemented.
A41/A42/A45–A48 execute; A43/A44 remain refused record prototypes. Owning-result
lazy/checked borrowed accessors and multi-owner initialized-prefix cleanup remain
open. The next coherent campaign should unify field-derived rollback/cleanup and
owned checked result channels, then complete those missing application gates.
See current evidence and
all 35 question boundaries. This checkpoint preserves
historical Surge-3 PARTIAL and LAZY Q4 HELD/INCOMPLETE and defers self-hosting.

## Contents

- [1. The current vision for Astra](#1-the-current-vision-for-astra)
- [2. How to read and maintain this plan](#2-how-to-read-and-maintain-this-plan)
- [3. Where Astra stands now](#3-where-astra-stands-now)
- [4. Execution path and upcoming milestones](#4-execution-path-and-upcoming-milestones)
- [5. Dependency checkpoints and measures of readiness](#5-dependency-checkpoints-and-measures-of-readiness)
- [6. Open-question register](#6-open-question-register)
- [7. Roadmap adherence and change control](#7-roadmap-adherence-and-change-control)
- [8. Revision policy and working record](#8-revision-policy-and-working-record)
- [9. Sources and provenance](#9-sources-and-provenance)

Read the vision first. Use the status labels to distinguish current implementation from the adopted direction. The decision register is intentionally open: a planning handle is not an approved syntax or a completed feature.

# 1. The current vision for Astra

## 1.1 A language designed for human–AI cooperation

Astra is a native-first systems and application language whose primary human-facing goal is to make efficient, deterministic, safety-oriented code easy to read and review. It should let a human understand agent-produced code in terms of its actual purpose: an image, a kernel, a device, a task, a document or a resource—not anonymous buffers, bookkeeping flags and dense type punctuation.

The preferred surface is familiar and C#/Vala-like: readable words, ordinary statement structure, useful local inference and low annotation overhead. Astra is not trying to reproduce all of C++, Rust or Vala. It should absorb complexity inside the compiler when doing so removes redundant source detail without hiding allocation, mutation, ownership transfer, lifetime risk or other meaningful behavior. “The Crayola of systems languages” describes that accessibility, not weak semantics or a simplistic implementation. [R1, §§54, 62, 64–68]

Reviewability is a design criterion, not a final cosmetic pass. Every major feature must answer: **what does ordinary Astra code look like after this exists?** A feature that is easy to represent internally but forces routine application code into workarounds is not complete merely because its tests pass.

## 1.2 Native performance, precise behavior and pragmatic safety

Astra aims to make C/C++-class efficiency attainable while catching a substantial fraction of ownership and lifetime mistakes statically. The aspiration of “roughly 80% of Rust’s safety with far less cognitive overhead” is deliberately rhetorical. It is not a measured safety percentage, a formal soundness claim or a promise that unchecked foreign code becomes safe. Likewise, universal performance parity has not been established. Specific guarantees and costs must be stated and measured. [R1, §§57, 64]

Deterministic ownership and RAII are foundational. Cleanup should normally follow scope and responsibility rather than a programmer-maintained list of cleanup actions. The same principles apply to memory, foreign handles, files, sockets, locks, GPU objects and hardware resources as those domains are implemented. Copying a value, borrowing access and transferring ownership are different operations; inference must not erase those distinctions.

The preferred native object direction is unique, stable-identity ownership by default, with shared lifetime as an explicit additional policy. Borrowing is an access relationship, not a second object identity or an expiration-aware weak reference. Ownership, nullability, mutability, dispatch and storage placement are separate design dimensions. The likely place for a common lifetime policy is the type declaration, but its exact syntax and permitted use-site exceptions remain open. [R1, §66]

Ordinary structs should be unsurprising values. Copyability, move-only behavior and recursive cleanup should follow their fields where derivable. No `SimpleType` annotation is required for the ordinary copyable case. Native objects need not be heap-allocated merely because they have identity; nor should object construction be permanently tied to one global allocator. [R1, §§31–33, 67]

## 1.3 A complete application language, not only a numerical subset

The destination includes semantic properties, first-class lazy properties, native callables, modern async, reusable owning data structures, practical text and byte processing, recoverable errors, larger-project organization and usable development tools. Async is a founding requirement. Its native model is a compiler-generated state machine with an explicit frame and an executor, not the historical GLib begin/end ABI. Lazy evaluation is also a compiler-semantic feature, not merely an opaque caching wrapper. [R1, §§17–19, 24–25]

C interoperability is permanent and first-class. VAPI-style typed declarations and eventual GObject/GIR adapters belong at explicit boundaries. Astra does not inherit GObject as its native object model, GType as universal identity, or generated C as the authority for native semantics. Foreign contracts must preserve lifetime and ABI meaning rather than merely match machine widths. [R1, §§3–5, 12–16]

## 1.4 Desktop, numerical and embedded uses are all real targets

Astra must eventually support a genuine freestanding profile without requiring an operating system, GLib/GObject, garbage collection, a global heap, threads, reflection or a heavyweight unwinder. Optional runtime services must remain optional. LLVM is the initial machine backend; it does not substitute for a public target/link workflow or execution qualification on the actual hardware. [R1, §§9, 35–37]

AEP remains a primary numerical/DSP workload. Maelstrom-ng and Dreamcast/SH-4 remain primary embedded constraints. CAD is now a valuable additional application witness, not a replacement for either and not evidence that asynchronous, object-heavy or embedded programs are finished. The guiding principles remain:

**Native first. Compatibility at the boundary. Pay only for what is used. Keep useful semantics visible long enough to optimize them. Never misstate ownership, ABI, safety or measured performance.** [R1, §§10, 52–53, 63]

# 2. How to read and maintain this plan

## 2.1 Status is explicit

| Label | Meaning in this document |
| --- | --- |
| **Delivered** | Implemented within the stated domain and supported by an accepted qualification record. It does not mean unrestricted feature composition. |
| **Submitted** | A concrete campaign has been issued, but no accepted completion is recorded here. |
| **Planned** | Part of the adopted direction. Exact syntax, boundaries, dependencies and acceptance still require a bounded submission. |
| **Candidate** | Worth evaluating, but its inclusion or final semantics are not settled. |
| **Open** | A recorded decision that must be resolved before the named implementation boundary. It is not permission to guess. |

COMPILE-PROFILE-1 is accepted as a **Delivered measurement campaign**, with no production compiler behavior change. DOCS-SYNC-1 is **Submitted / acceptance pending**; completion of repository work does not imply user acceptance. ASYNC-CONTRACT-1, CALLABLE-1 and ASYNC-1 remain Planned and unimplemented. Future campaign labels below are planning handles, not reserved ADR numbers or promises of one commit’s implementation scope. A group may be split when that materially reduces risk. No calendar dates or completion percentages are assigned. [R10] [R11]

## 2.2 Distinguish current contracts from future intentions

Current code and its latest applicable qualification establish what the accepted compiler does. The founding Bible and this roadmap establish what we intend to build. A future intention does not silently change an existing contract. Conversely, an old temporary restriction is not a permanent design veto.

When documentation conflicts, record the conflict, inspect the current implementation and applicable later decision, then reconcile the living guide explicitly. Preserve historical reports as historical evidence. In particular, this document does not revive obsolete source restrictions or claim that deleted build artifacts still exist. [R2, S12] [R3]

Open questions in section 6 elaborate the unresolved areas already identified by the vision and roadmap. Their alternatives are discussion prompts, **not newly approved semantics**. A question is closed only by an explicit decision, recorded rationale and the appropriate qualification—not by an example that happens to use one spelling.

# 3. Where Astra stands now

## 3.1 Accepted baseline and evidence limits

COMPILE-PROFILE-1 is the latest accepted repository delivery, at `9a8d393b7e7add7b8a5c1233785c3ea9f46d5a0a` (tree `9551b6d56cb1e4e92b297ba032dfdfa5d3fa39c7`). OWN-SWAP-1 remains the latest delivered language feature, at `ca7c2301c60f92185e1c8689b3d41f470ee92b0f`. Its two historical strict builds each passed 9,099 tests. Those receipts lack a complete historical compiler dynamic-library hash manifest; later current dependency freezing does not make them new dependency-exact suite reruns. CAD I1 passed the original 13 acceptance entries, 37 controls and 20,560 retained exact native observations. This revision relies on those scoped reports and its own focused checks. DOCS-SYNC-1 remains acceptance pending. [R3] [R4] [R10] [R11]

The source audit examined `astra.tar.xz`, SHA-256 `94fbb06549f3953c84796163e947e6d846e6cbf8d7018e974e36c1237c2b64c3`. It contains 3,733 regular files and no Git metadata. The separate delivery receipt records 3,734 source members. The audit does **not** assert package-level identity or infer a missing file. Its OWN-SWAP and APP-CAD-2 reports match the separately supplied reports. [R2]

The public compiler remains a Vala/C Stage-0 implementation. Its host dependencies are not automatically application runtime dependencies. The selected compiler license is `Apache-2.0 WITH LLVM-exception`; the founding document’s earlier undecided-license text is historical. This says nothing new about licensing imported application assets. [R2, S12]

## 3.2 Delivered foundations and their remaining boundaries

| Area | Delivered now | Still incomplete |
| --- | --- | --- |
| Native compiler | Semantic ownership/storage, Core, CFG/SSA, independent native/C plans and LLVM lowering. | Public optimized builds, target/object workflow, source-debug experience and self-hosting. |
| Numerics and vectors | Exact integer and f32/f64 semantics, conversions and literal suffixes; current SIMD/mask/DSP operations. | i64/u64, pointer-sized types, f64 vectors and broader explicit arithmetic/optimization policies. |
| Source ergonomics | `var`, compile-time `const`, generic call inference, supported implicit native borrowing, multi-source input. | Some unresolved-generic inference, conventional iteration/selection constructs, modules and proposed readability features. |
| Record values | Nested structs, copying, native value boundaries, generic records, and record collections. | Ownership-bearing fields with derived move-only behavior and cleanup. |
| Native objects | Identity, direct methods, init/deinit, lexical/caller-provided storage, bounded ownership/results. | General allocated unique objects, child-object ownership, broader moves, dispatch/interfaces, shared/weak policies. |
| Arrays and generics | Fixed arrays, buffers, slices, borrowed/owned generic arrays and ordinary production/algorithm helpers. | Generic owning abstractions, general owner borrowing, resizing and nontrivial element lifetimes. |
| Text and diagnostics | UTF-8 views, static results, validated arguments, output and source-aware assertions. | Owned/generated text, general text fields/collections, byte input, parsing/formatting and recoverable error composition. |
| Properties and async | Computed properties with exact accessor identity. | Lazy/ownership-aware/virtual property families; native callables and async are not implemented. |
| Foreign/platform boundary | Selected C/VAPI scalar, floating, handle/raw-pointer and explicit borrowed-text contracts. | Broader typed pointer/aggregate/callback coverage, GObject/GIR adapters and embedded qualification. |
| Real applications | Full CAD native-state I0 and descriptor-swap I1 qualification. | Event-driven, rich-object, text-heavy, AEP and Maelstrom-ng acceptance. |

For the present source-linked implementation contract, use the [capability matrix](language/capabilities.md). The summary above retains the original audit’s domains and restrictions, verified against current source identities in DOCS-SYNC-1; it does not extrapolate from milestone names. [R11] Generic specialization becomes existing concrete operations before CFG; arrays are not automatically admissible as plain generic `T`, and read-only deep-borrowed `string[]` is not a mutable generic numeric/record slice. [R2, S01–S10] [R6]

## 3.3 Three distinctions that must remain visible

**A native backend is not yet a public optimized toolchain.** The inspected driver has no ordinary optimization selection, object-only, target or source-debug option. It creates the target machine with `CodeGenOptLevel.NONE`; the normal route does not run an LLVM IR optimizer pipeline. Internal O2/FMA test harnesses do not change that public status. Compiler latency, generated-program optimization and deployment tooling are separate campaigns. [R2, S03]

**Value copying is substantially complete; resource-bearing values are not.** Plain records need no `SimpleType` marker and can cross generic/native boundaries. A future record containing owned resources must derive different move and cleanup behavior. Current copyability does not imply equality, ordering or default construction. [R1, §67] [R2, S07] [R6]

**The CAD result is strong but scoped.** The native-state port preserved the retained numerical contract and improved CLI medians in two matched cases, while compilation and code size increased. The later owner swap removes payload rotation, but establishes no clear whole-CLI timing gain. Neither result proves universal performance parity or readiness for every application class. [R3] [R5]

# 4. Execution path and upcoming milestones

## 4.1 Immediate priorities

The user-approved 2026-10-04 amendment places the shared enum/error foundation before source async. CALLABLE-1 and its V01–V03 correction are delivered internal foundations at the accepted baseline `a7cb205b6ac9b4341455f0798f4af041206de134`. Review [the enum/error contract](architecture/enums-and-errors.md), then prepare useful ENUM-1, the specifically required ENUM-OWN-1 composition, ERROR-1 and revised ASYNC-1 with A+C, followed by ASYNC-IO-1. LAZY-1 stays near-term; PERF-01 is Candidate / not scheduled. This bounded sequence does not suspend the other six coordinated tracks.

| Order / position | Campaign | Intended outcome |
| --- | --- | --- |
| Accepted measurement | **COMPILE-PROFILE-1 — Delivered measurement** | Qualified all 330 samples and emitted-program parity; production compiler behavior unchanged. Its performance lead is Candidate / not scheduled, below. [R10] |
| Current housekeeping | **DOCS-SYNC-1 — Submitted / acceptance pending** | Adopt this living master and preserved snapshots, correct live contradictions, qualify the bounded milestone label, and prepare the async handoff. No language question closes. [R11] |
| Current contract | **ENUM-ERROR-CONTRACT-1 — Proposed** | One shared enum/error recommendation and bounded model; detailed semantic/ABI approval pending. |
| Next implementation after review | **ENUM-1 → ENUM-OWN-1 → ERROR-1 — Planned** | Useful payload enums, exact owning/generic outcome matrix, then synchronous checked errors; exit criteria. |
| Delivered internal foundation | **CALLABLE-1 / CALLABLE-1-R1** | Exact code/environment/lifetime association and V01–V03 retained verification; no source callable/task API. |
| Return to Track A | **Revised ASYNC-1 — Planned** | Real suspension/resumption and virtual completions using shared enums/errors and both explicit handling plus try await; source/lifecycle details still require review. |
| Application closure | **ASYNC-IO-1 — Planned** | Execute a real asynchronous operation and an event-driven application, not only a synthetic state machine. |
| Near-term companion | **LAZY-1 — Planned** | Implement first-read evaluation/cache semantics with explicit lifecycle, failure and reentrancy rules. |

This is a priority order, not an assertion that every full callable/closure or object feature is a hard prerequisite for async. ASYNC-CONTRACT-1 must identify the smallest sufficient foundation. It must not expand into a requirement to finish shared ownership, reflection, all threading or a package system first. Error behavior should be coordinated with ERROR-1 early, even when its first implementation is deliberately narrow. [R1, §§19, 24–25, 34] [R7]

<a id="track-a"></a>
## 4.2 Track A — Async, callables and lazy evaluation

**Purpose:** deliver the founding language features that the numerical checkpoint did not exercise.

CALLABLE-1 must preserve a function together with any environment and lifetime/destruction responsibility. A native closure is not just an untyped C function pointer. ASYNC-1 must account for owners and borrows that remain live while execution is suspended, and for every permitted completion or cancellation path. Optional event-loop adapters must not define the native task ABI. [R1, §§24–25]

The preferred first scope is cooperative and single-threaded, with explicit executor ownership. Threaded execution remains a later qualified extension. A test executor is useful, but ASYNC-IO-1 closes the usability loop with actual external completion or timing. The exact operation, application and task syntax remain decisions in Q01–Q06.

LAZY-1 should begin with a bounded value/lifetime domain that the compiler can prove sound, while documenting how later owning values will compose. A successful getter is not enough: recursive first access, failed initialization and destruction of cached state need explicit behavior. Ownership-aware property expansion may follow without blocking a simple initial lazy capability.

**Closure evidence:** source examples with ordinary control flow; deterministic owner/frame/cache cleanup; rejected invalid borrows; real resumed execution; independent stage/ABI checks; and measured dependencies. No implicit claim of general concurrency safety. **Open decisions:** Q01–Q06, Q16.

<a id="track-b"></a>
## 4.3 Track B — Complete owned application data

**Purpose:** let an abstraction own its natural state rather than forcing callers to coordinate it manually.

| Campaign | Bounded objective | Dependency or scope boundary |
| --- | --- | --- |
| **OBJ-ALLOC-1** | Stable, independently allocated unique objects, alongside existing lexical/caller storage. | Select construction/storage/failure policy; do not make every object require a heap. |
| **OBJ-FIELD-2** | Parents owning child objects with transitive lifetime and safe replacement. | Build on the chosen object ownership/storage contract. |
| **STRUCT-MOVE-1** | Ownership-bearing struct fields with derived move-only transport and recursive cleanup. | Preserve plain copyable records; resolve partial-move and initialization rules. |
| **GEN-BORROW-1** | Non-consuming generic access to ownership-bearing values. | Preserve implicit-borrow ergonomics without changing plain value `T` into a reference. |
| **GEN-OWN-2** | Q11E admits one incoming-owner local; broader owner-local composition remains open. | Reuse ownership authority rather than create a second generic lifetime system. |
| **GEN-MEMBER-1** | Useful generic type/member abstractions, including required generic class/method forms. | Scope from real container/application requirements. |
| **CONTAINER-1** | A reusable owning collection with capacity/growth and explicit view invalidation. | Requires adequate owning state; not merely an unchecked `realloc` wrapper. |

These are planned additions, not claims that current `Box<T>` is a heap box or a generic owning class. The source still rejects generic classes/members and owned struct fields, and restricts direct generic owner locals and borrowing. [R2, S04, S07]

A collection’s growth policy, allocation failure and element movement must be visible enough to review. Type declarations should supply common policy where appropriate; individual uses should not restate derivable copy/move/cleanup properties. General extraction from an owned field remains a separate decision: the accepted buffer `swap` solves bounded exchange without approving arbitrary temporary field holes. [R1, §§66–68] [R3]

**Closure evidence:** a real owning abstraction; moves/replacement/normal errors; dependent-view rejection; no duplicated cleanup; and costs of growth/copying. **Open decisions:** Q07–Q12, Q19–Q20.

<a id="track-c"></a>
## 4.4 Track C — Everyday text, bytes and errors

**Purpose:** make complete native applications comfortable from input through persistent state to output.

| Campaign | Bounded objective | Dependency or scope boundary |
| --- | --- | --- |
| **ERROR-1** | A reusable recoverable error/result model compatible with RAII, C and async. | No mandatory heavyweight unwinder; syntax and representation remain open. |
| **TEXT-OWN-1** | Constructed/owned text and safe borrowed views, with a route to persistent storage. | Preserve the current UTF-8 invariant and distinguish owner from view. |
| **BYTES-IO-1** | Practical byte input/output and file/external-data boundaries. | Coordinate status/error and allocation policies; bytes are not automatically text. |
| **TEXT-LIB-1** | Parsing, searching, splitting and bounded text operations. | Specify units, encoding boundaries and borrow lifetimes. |
| **FORMAT-1** | Scalar formatting and message construction without bespoke C bookkeeping. | Choose allocation, format validation and numerical rendering contracts. |
| **ENUM-1 / CONTROL-1** | Named alternatives and practical selection/iteration. | Define interaction with error values and ownership; no incidental new type system. |

The order within this track is deliberately coupled. An owned text builder and a move-only aggregate may share a storage foundation; a simple byte-I/O boundary need not wait for an extensive string library. ERROR-1 and ASYNC-CONTRACT-1 must not invent incompatible completion/error conventions.

Current `string` is an immutable UTF-8 view with static-only native results, not a general string owner. Current allocation actions are fatal, not recoverable results. Source-aware assertions are diagnostics for failed conditions, not the complete application error model. [R2, S08] [R8]

**Closure evidence:** a text-heavy command-line tool and a file-processing tool written mostly in Astra, with meaningful normal error returns, honest platform adapters and complete cleanup. **Open decisions:** Q05, Q13, Q17–Q21, Q30.

<a id="track-d"></a>
## 4.5 Track D — Native objects, properties and adapters

**Purpose:** complete object-oriented application facilities without imposing their costs on every type.

| Campaign | Bounded objective | Dependency or scope boundary |
| --- | --- | --- |
| **DISPATCH-1 / INTERFACE-1** | Native virtual dispatch/interfaces and only the required metadata. | Unique lifetime must not forbid polymorphism; shared lifetime must not be required for it. |
| **PROP-LIFE-1** | Borrowing/owning property results and parameters, including deferred Resource-valued properties. | Choose copy/borrow/transfer and backing-lifetime rules explicitly. |
| **PROP-COMPOSE-1** | Broader property values/receivers and justified stored/automatic forms. | Preserve accessor effects and semantic identity; do not silently cache ordinary getters. |
| **SHARED-1** | Opt-in shared lifetime with explicit cost and threading contract. | Keep unique classes free of mandatory reference counting. |
| **WEAK-1** | Expiration-aware references and safe acquisition of a live referent. | Distinct from call-bounded borrowing; coordinate with shared/object destruction. |
| **GOBJECT-1 / GIR-1** | Typed method/property/signal adapters, stable wrapper identity and lifetime translation. | GObject remains foreign; cross-boundary cycles and callbacks require explicit rules. |

LAZY-1 is the near-term semantic property milestone in Track A. It is not replaced by this later ecosystem work. Current computed properties retain exact accessor identity but exclude lazy storage, ownership-bearing values and virtual dispatch. [R2, S06]

The exact native inheritance/interface model, shared-policy spelling, weak-upgrade result and property ownership syntax remain open. GObject/GIR are intended capabilities, but a full compatibility ecosystem is not a prerequisite for initial native async or a freestanding core. [R1, §§11, 14–19, 33, 66]

**Closure evidence:** a nontrivial native object application, then a real boundary adapter with verified identity/lifetime and dependency costs. **Open decisions:** Q09, Q12, Q14–Q18, Q24.

<a id="track-e"></a>
## 4.6 Track E — Public systems and numerical toolchain

**Purpose:** turn internal compiler capabilities into an explicit usable deployment path.

| Campaign | Bounded objective | Dependency or scope boundary |
| --- | --- | --- |
| **INT64-1 / SIZE-1** | Wider integers and size/pointer-sized concepts with exact conversions and layout rules. | Do not silently change existing `int` or array-count semantics. |
| **CABI-EXT-1** | Required integer, typed pointer/buffer, aggregate and callback boundaries. | Drive scope from real APIs; native type support alone is not a foreign ABI proof. |
| **DRIVER-TARGET-1** | Public object emission, target selection and cross-link/startup workflow. | Select actual supported targets and explicit dependencies. |
| **OPT-PIPELINE-1** | A supported optimized application-build route. | Preserve exact numeric, effect, trap and ownership contracts; compiler-latency profiling is separate. |
| **ALLOCATOR-1** | Explicit arena/pool/custom/static allocation strategies. | Allocation policy and language ownership must remain distinct. |
| **EMBEDDED-1** | Real startup, runtime-dependency, hardware-access and target execution qualification. | A host-only internal startup witness does not satisfy this. |
| **SIMD-POLICY-1** | Remaining vector/memory operations and explicit fused/relaxed arithmetic policies. | Preserve existing exact/default behavior and target-independent semantics. |

The source lacks i64/u64 and pointer-sized builtins, has no f64 vectors, and retains fixed-array extents of 1–1024. The public optimization/object/target gaps are separate from the existing host LLVM machinery. Selected C types and text contracts work; foreign bool, typed data/struct pointers and broader aggregates remain restricted. [R2, S02–S03, S09]

The first hardware/target sequence is an open decision, but Maelstrom-ng/Dreamcast cannot disappear behind a convenient desktop-only implementation. Low-level MMIO, volatile access, interrupts and atomics must be qualified when the selected workload requires them. Explicit vector/saturation operations already present must not be listed as wholly missing merely because broader numerical policies remain open. [R1, §§9–10, 26–33, 52–53]

**Closure evidence:** public command-line use, matched target layouts/ABI, real code generation and execution, and a measured no-unused-runtime profile. **Open decisions:** Q22–Q27.

<a id="track-f"></a>
## 4.7 Track F — Projects, tools and self-hosting

**Purpose:** make larger programs and the language’s own development practical.

| Campaign | Bounded objective | Dependency or scope boundary |
| --- | --- | --- |
| **MODULE-1** | Namespaces, visibility and explicit source dependencies. | Current multi-file compilation is one global program. |
| **Separate compilation — later bounded campaign** | Reusable compiled units and exact interface/ABI/version boundaries. | Not synonymous with namespaces or linking an external object. |
| **TOOLS-1** | Formatter, editor support, source-level debugging and practical build workflow. | Audit existing tools first; avoid assuming either complete support or universal absence. |
| **AEP / Maelstrom-ng qualification gates** | Real numerical/event-driven and embedded workloads. | CAD remains a regression, not the only design authority. |
| **SELFHOST-1** | Astra compiler source migration, Stage 1/Stage 2 equivalence and reproducible bootstrap. | Begin when Astra can express the compiler cleanly; not a prerequisite for useful releases. |

The inspected tree provides neither a module/private-visibility system nor an identified formatter/language-server/source-debug implementation. That is an archive-scoped finding, not a statement about every external tool. The compiler remains bootstrapped using ordinary Vala rather than the frozen experimental ancestor. [R2, S10, S12]

**Closure evidence:** an out-of-tree multi-component project, clear diagnostics/debugging and repeatable builds. Self-hosting later adds stage equivalence rather than substituting for application/target tests. **Open decisions:** Q28–Q29, Q35.

<a id="track-g"></a>
## 4.8 Track G — Readability and safe-default candidates

**Purpose:** retain the later Vala-inspired ideas without falsely marking their exact semantics as decided.

| Planning handle | Direction | Current status |
| --- | --- | --- |
| **COMPARE-CHAIN-1** | Mathematical comparison chains with once-only shared operands and defined short-circuiting. | Implemented for exact scalar relational chains in ADR 0122; vector chains and implicit promotions remain excluded. |
| **NULLABILITY-1** | Evaluate non-null-by-default references and explicit nullable forms with flow refinement. | Explicit nonnull contracts are implemented in ADR 0127; existing nullable defaults remain and migration requires a separate decision. |
| **WITH-1** | Group receiver operations without repeated long access paths. | Bounded explicit qualified receiver captures are implemented in ADR 0126; no leading-dot lookup or escaping alias. |
| **REGEX-1** | Optional pattern literals and a well-specified matching component. | Candidate after basic text facilities; no mandatory regex engine or JIT. |

These labels organize the earlier discussion; they do not authorize syntax already rejected by the current parser. The suggested leading-dot `with` spelling and `shared class` spelling remain proposals. Jai-style `:=` declarations were not adopted; familiar `var` and typed declarations remain the direction. [R2, S11] [R9]

Small readability campaigns may be interleaved when their contracts are ready. They should not displace the major founding features indefinitely, nor be dismissed indefinitely as “only syntax.” **Open decisions:** Q12, Q30–Q34.

<a id="perf-01"></a>
## 4.9 Supporting backlog — PERF-01, Candidate / not scheduled

**PERF-01 — SSA borrowed-buffer interval traversal** records the accepted study’s
local engineering lead without scheduling a campaign or creating an eighth
language track. It is not a blocker to ASYNC-CONTRACT-1. Public generated-program
optimization remains OPT-PIPELINE-1 in Track E. [R10]

The unchanged [study](compiler/latency-study.md) and
validation preserve three evidence levels:

1. **Measured phase increase:** ordinary compile/link medians are P **271.987 ms**,
   I0 **533.103 ms**, I1 **495.324 ms**. Four independent SSA verifier calls
   account for approximately **69% of the additional native-state cost** in the
   diagnostic compiler’s per-sample grouped measurements. The grouped SSA
   medians are P 56.325 ms, I0 236.611 ms, I1 208.866 ms; increases are
   180.286 / 152.542 ms. This is neither 69% of all compilation time nor a
   promised 69% speedup.
2. **Supported mechanism:** source inspection and executed-work profiles support
   repeated borrowed-buffer interval traversal. The ordinary subroutine wall
   time and replacement profitability were not established.
3. **Untested improvement:** a separately authorized campaign may evaluate
   verifier-local adjacency/reverse worklists. No patch, persistent verification
   cache, IR change or omitted verification is authorized by this entry.

Any future experiment must preserve literal-aware edges, owner-read boundaries,
every per-use invalidation proof, diagnostic behavior and all independent
verifier entry calls. A previously checked mutable program is not safe-reuse
authority. Relevant current code is
[interval verification](../bootstrap/ssa/ssa-verifier.vala) and
[literal-aware successors](../bootstrap/ssa/ssa-constructor-initialization.vala).

All 330 samples remain retained with qualified emitted-program parity; the study
performed no new full application corpus or pair of 9,099-test runs. Its 26 new
Memcheck invocations report zero errors/lost categories; one fatal non-unwinding
path retains reachable allocations. The inherited 5,001-local GLib control was
**not exercised**. Its 776,871,936 allocated bytes, including the 31,017,907-byte
compact archive, are historical retention observations, not this campaign’s
quota or a request to duplicate them. [R10]

# 5. Dependency checkpoints and measures of readiness

## 5.1 Dependencies to settle, not invent as excuses

| Intersection | Planning rule |
| --- | --- |
| Async, callables and errors | Agree the minimum completion/error/environment contracts first. Implement only the small prerequisite actually demonstrated by the first executor. |
| Owned objects, move-only records, text and containers | Share lifetime and storage authorities. Do not require every object feature before useful owned text, or build a second ownership system for a builder. |
| Lazy/property values and errors | Decide failed initialization, reentrancy and cleanup before supporting affected value domains. Do not equate ordinary getter calls with cached reads. |
| Shared/weak, callbacks and GObject | Make retention, cycles and safe acquisition explicit. Do not let a foreign callback define the native ownership model. |
| Sizes, C ABI, allocators and targets | Set exact widths, layout and destruction authority before claiming portability. A public target flag without qualified execution is insufficient. |
| Modules, tools and self-hosting | Source organization and debug usability can improve before self-hosting. Separate compilation and bootstrap are distinct commitments. |

These are planning dependencies. Their exact implementation edges are resolved at each contract checkpoint; they are not permission to expand the next submission into all connected tracks.

## 5.2 Readiness is demonstrated by programs

| Gate | Evidence required | Present position |
| --- | --- | --- |
| **Qualified numerical/native subset** | Typed state, precise numerics, deterministic ownership, installed consumption and a complete real workload. | Established for the supplied CAD scope and qualified host. |
| **Event-driven language** | Actual suspension, completion/cancellation, owner safety and a useful asynchronous operation/application. | Not delivered. |
| **Comfortable ordinary applications** | Text-heavy and file-processing tools with reusable state, meaningful recoverable errors, modest platform glue and usable build/debug workflow. | Partially enabled; major gaps remain. |
| **Systems/embedded readiness** | Public target/object/link workflow, hardware/runtime controls and actual target workload evidence without unused services. | Internal groundwork exists; full public path not delivered. |
| **Broader ecosystem maturity** | Appropriate shared/weak/dispatch/adapter facilities, larger projects, tooling and eventual bootstrap equivalence. | Planned; not a prerequisite for every smaller useful release. |

No gate is defined by reaching a test-count target. Performance, code size, compilation latency, memory use and human-review friction are separate observations. A successful numerical application cannot prove async unnecessary; a hosted application cannot prove freestanding readiness. [R1, §§39–42, 47, 68] [R3] [R5]

# 6. Open-question register

Every entry below is **OPEN** as of this version. “Direction” records an existing preference or constraint, not a final syntax decision. “Resolve before” identifies the affected contract milestone, not a calendar deadline. Newly discovered issues should receive a new ID; closed entries keep their ID and link to the decision that closed them.

## 6.1 Async and callable contracts

<a id="q01"></a>
### Q01 — Async source and task meaning

**Question:** What are the native declaration and suspension spellings, and what value does calling an async function produce? Does it begin immediately or require scheduling? Can a result be awaited more than once?  
**Direction:** Native state machine/frame/executor; readable surface. Neither Vala-style `yield` nor `await` spelling is frozen here.  
**Resolve before:** ASYNC-CONTRACT-1 / ASYNC-1. [R1, §25]

<a id="q02"></a>
### Q02 — Task completion, cancellation and abandonment

**Question:** Who owns a task, what happens when its owner disappears, and when is cancellation complete? Which code runs for success, error, cancellation and unobserved completion?  
**Direction:** Explicit ownership and deterministic permitted cleanup; no accidental detached work or retroactive promise of unwinding.  
**Resolve before:** ASYNC-CONTRACT-1; qualify in ASYNC-1 and ASYNC-IO-1.

<a id="q03"></a>
### Q03 — Borrows across suspension

**Question:** Which references/views may remain live across a suspension, and how is backing lifetime proven? What invalidates a field or nullability refinement? What changes when a task can migrate between executors or threads?  
**Direction:** Ordinary synchronous noescape proofs are not automatically suspension proofs. Start conservatively without pervasive lifetime punctuation.  
**Resolve before:** ASYNC-CONTRACT-1; any later threaded extension.

<a id="q04"></a>
### Q04 — Frame storage and executor boundary

**Question:** When are frames stack-, caller-, pool- or heap-backed? Who releases them, what allocation failures mean, and what minimal wake/completion protocol the first executor needs?  
**Direction:** Pay only for required storage; preserve a route to embedded/custom executors. Full shared ownership and a large runtime are not prerequisites.  
**Resolve before:** ASYNC-CONTRACT-1 / ASYNC-1; coordinate with ALLOCATOR-1.

<a id="q05"></a>
### Q05 — Errors across ordinary and asynchronous calls

**Question:** What is the recoverable result/error representation, how are payload owners transferred, and how do C errors and task failures map into it? What must callers explicitly handle?  
**Direction:** Deterministic behavior and no mandatory heavyweight unwinder. `Result`, tagged alternatives, `throws` and other spellings remain unselected.  
**Resolve before:** ERROR-1 and the async completion contract. [R1, §34]

**Checkpoint 2026-10-04:** Direction USER_APPROVED: ordinary structured enum errors and A+C propagation, with checked errors before source async. Exact capture/try/handler/ABI rules remain PROPOSED; Q05 stays OPEN. Contract/review.

<a id="q06"></a>
### Q06 — Callable captures and foreign retention

**Question:** How do function values distinguish no environment, bounded borrowed capture and owned escaping environments? How are copy, move and destruction represented? What may a C callback retain?  
**Direction:** Function/environment/lifetime form one logical value; no discarded capture or destruction channel. Choose the minimum useful first scope.  
**Resolve before:** CALLABLE-1; later CABI-EXT-1/GObject callback support. [R1, §24]

## 6.2 Object, aggregate and generic ownership

<a id="q07"></a>
### Q07 — Allocated unique object construction

**Question:** How does source select independently allocated storage while preserving cheap lexical construction? What are failure, move/rebind, identity and promotion rules?  
**Direction:** Unique deterministic ownership; construction is not permanently one global heap. Existing lexical/caller-provided behavior is not silently reinterpreted.  
**Resolve before:** OBJ-ALLOC-1; coordinate with Q25.

<a id="q08"></a>
### Q08 — Owned child objects and field extraction

**Question:** How are child fields initialized, replaced and destroyed? Can ownership be extracted, and what restores a valid field? Which self-/cross-links are allowed?  
**Direction:** Preserve exact cleanup and valid storage. Buffer `swap` is not general field-move authorization. Non-owning links require independent lifetime rules.  
**Resolve before:** OBJ-FIELD-2; any general extraction extension.

<a id="q09"></a>
### Q09 — Declaration-level lifetime policy

**Question:** How is an abstraction’s unique/shared default declared, and are exceptional use-site policies permitted? How does this interact with construction, generics and adapters?  
**Direction:** Declaration-level common policy is preferred; `shared class` remains a possible spelling, not frozen grammar. Ownership must remain separate from dispatch and nullability.  
**Resolve before:** SHARED-1 and broader object-policy changes. [R1, §66]

<a id="q10"></a>
### Q10 — Derived move-only structs and partial state

**Question:** How do owning fields determine whole-value move/cleanup, partial initialization, partial moves and failure paths? How is a move distinguished from an identity-object transfer?  
**Direction:** Derive copyability/movability/cleanup from fields when possible, with useful field-path diagnostics; no redundant `SimpleType` or move-only marker for the ordinary case.  
**Resolve before:** STRUCT-MOVE-1. [R1, §67]

**Checkpoint 2026-10-04:** Coordinate enum whole moves, initialized-prefix cleanup and incoming-first replacement with future owning records; ENUM-OWN-1 does not implement general STRUCT-MOVE. Q10 stays OPEN. Contract/review.

**Finite checkpoint 2026-10-14:** Synchronous nongeneric local records with one
owned Resource and scalar companions support complete Resource-last nonthrowing
initialization, whole-local moves and lexical cleanup. The explicitly approved
Q10B extension covers later checked calls/throws and scope-correct try/catch
cleanup. Checked initialization/rollback, nested or generic ownership,
owner-field extraction, receivers, aggregate ABI and async transport remain
deferred. Q10 stays OPEN. Finite checked proof.

<a id="q11"></a>
### Q11 — Generic borrowing and owner-local composition

**Question:** How can generic code borrow a direct ownership-bearing value without consuming it, and store a local owner safely? How do default borrowing, capabilities and ordinary copied `T` coexist?  
**Direction:** Extend shared semantic authorities, not a second generic ownership system. Do not retroactively reinterpret current plain value transport.  
**Resolve before:** GEN-BORROW-1 / GEN-OWN-2 / GEN-MEMBER-1.

**Checkpoint 2026-10-04:** ENUM-OWN-1 specifies a bounded direct owned-array payload premise and applied enum locals; no general owned T or borrowed T is selected. Q11 stays OPEN. Contract/review.

**Checkpoint 2026-10-14:** The user approved `Q11A-RESOURCE-CLASS-BORROW` after reviewing the Class lifetime argument. GEN-BORROW-1 implements one synchronous call-scoped borrowed Ownable T for exact nominal Resource/Class owners, including heap Class borrowing, with nonthrowing scalar/void helper signatures. Forwarding preserves owner identity and cleanup; escape, overlapping consumption and coroutine loan contexts reject. Heap generic consuming provenance, generic owning locals, multiple/stored loans and generic members remain deferred. Q11 stays OPEN. [Decision](decisions/0094-call-scoped-generic-borrowing.md), [lifetime argument](gen-borrow-1-class-design.md), [execution recipe](../tests/gen-borrow-1/README.md).

**Later checkpoint 2026-10-14:** The user approved `Q11B-HEAP-CLASS-CONSUMER` after reviewing the provenance design. GEN-OWN-2A adds one direct exact heap Class owned-T consumer, with synchronous/nonthrowing scalar/void boundaries and compile-time lexical/heap instance separation. Existing destruction/free and borrowing authorities remain in use. Heap generic results/forwarding/recursion, owning T locals, multiple owner transport and generic members remain deferred. Q11 stays OPEN. [Decision](decisions/0095-finite-generic-heap-class-consumption.md), [design](gen-own-2a-heap-design.md), [execution recipe](../tests/gen-own-2a/README.md).

**Forwarding checkpoint 2026-10-14:** The user approved `Q11C-HEAP-FORWARD-NORESULT` before implementation. GEN-OWN-2B permits one structural owned-T forwarding site per synchronous/nonthrowing scalar/void helper, with independently qualified acyclic transfer graphs and original heap provenance at each specialization. Conditional retained paths keep existing cleanup; same-T lexical/heap bodies stay distinct. Heap generic results, owner locals, recursive/loop forwarding, multiple sites/formals, aggregate ownership and generic members remain deferred. Q11 stays OPEN. [Decision](decisions/0096-finite-generic-heap-class-forwarding.md), [lifetime design](gen-own-2b-heap-forward-design.md), [execution recipe](../tests/gen-own-2b/README.md).

**Direct-result checkpoint 2026-10-14:** The user approved bounded Q11D and its two exact historical fixture replacements before implementation. GEN-OWN-2C permits one direct return of the exact incoming heap Class owner into a fresh named concrete owner. Existing instance identity selects separate heap/lexical result domains; heap results reuse the original native PTR with no candidate, copy or runtime origin tag. Semantic/Core independently prove source and receiver, and CFG/SSA/native preserve capture, current pointer, cleanup and exact origin. Heap result forwarding/recursion, generic owner locals, inline producers, multiple sites/formals and broader composition remain deferred. Q11 stays OPEN. [Decision](decisions/0097-direct-generic-heap-class-results.md), [lifetime/ABI design](gen-own-2c-heap-result-design.md), [execution recipe](../tests/gen-own-2c/README.md).

**Owner-local checkpoint 2026-10-15:** The user approved Q11E option A and five exact historical negative replacements after the fresh baseline and source-backed lifetime proof. GEN-OWN-2D admits one explicitly typed local initialized by direct move of the single incoming owned T, with Resource and exact heap/caller-backed Class domains. Normal scope/early exits retire the local; a completed borrow and one terminal consuming site preserve the original handle/pointer. Same-T domain keys and independent Core/CFG/SSA/native authorities remain in use. Local owned results, multiple owners/sites, rearm, recursive/loop transfers, generic members/collections and broader composition remain deferred. Q11 stays OPEN. The next application-facing checkpoint is a separately pinned owning collection requirement review across GEN-MEMBER-1, CONTAINER-1 and TEXT-OWN-1. [Decision](decisions/0098-one-generic-owner-local.md), [approved proof](gen-own-2d-owner-local-design.md), [execution recipe](../tests/gen-own-2d/README.md).

**Application checkpoint 2026-10-15:** APP-DIAG-COLLECTION-0
executes a concrete bounded diagnostic bag with existing immutable snapshots and
records the owning-element and generated-byte/text gaps. Its recommendation is
a separately approved TEXT-OWN-1A byte-to-owned-message boundary, then concrete
container growth and evidence-driven generic member reuse. This is a contract
and witness only; no new semantics/API or closure of Q11/Q19/Q20 is selected.
All tracks and existing implementation/target qualification limits remain.

**Finite Q11F/Q20B checkpoint 2026-10-16:** The user approved one exact-Class
generic bag declaration with owning slots and five direct operation patterns.
Closed Diagnostic and Utf8Message applications have separate nominal identities,
members and cleanup chains, explicit 2→3 growth, and concrete call-scoped
inspection helpers. General generic members, inheritance, generic owning records,
persistent loans and richer containers remain deferred; Q11 stays OPEN.
[Design](decisions/0101-exact-class-generic-bag.md),
[guide](language/generic-class-bags.md),
[qualification recipe](../tests/gen-member-1a/README.md).

<a id="q12"></a>
### Q12 — Nullability, refinement and compatibility

**Question:** Should references become non-null by default, with what nullable spelling and migration rules? Which checks refine locals/fields across calls or suspension? What checked narrowing or explicit unsafe escape is allowed?  
**Direction:** Strong safe-default candidate; current Class/Resource contracts are nullable. Non-null does not prove lifetime, and moved is not merely null.  
**Current bounded implementation:** [explicit native nonnull contracts](decisions/0127-explicit-native-nonnull-contracts.md), with local flow and independent stage proofs. Current references remain nullable by default. Safe-default migration, general field/async/Weak refinement and broader signatures remain open. [R2, S05]

<a id="q13"></a>
### Q13 — Recoverable allocation

**Question:** How can allocation failure return a usable error rather than terminate? How does that result compose with arrays, objects, libraries and custom allocators?  
**Direction:** Existing `new ... else void_call(...)` is intentionally fatal and allocation-site-local. Do not silently change it into retry, fallback storage or recovery.  
**Resolve before:** Any recoverable-allocation extension under ERROR-1 / ALLOCATOR-1. [R8]

**Checkpoint 2026-10-04:** Checked errors do not make new/else fatal allocation recoverable. A fallible allocator remains a separately reviewed extension. Q13 stays OPEN. Contract/review.

## 6.3 Shared lifetime, dispatch and properties

<a id="q14"></a>
### Q14 — Shared lifetime and weak acquisition

**Question:** Which shared operations are allowed, which counts are atomic, and what is the cycle policy? How does a weak reference obtain a live owner without racing destruction?  
**Direction:** Optional explicit cost; weak is expiration-aware, borrow is lifetime-bounded. A minimal shared implementation must not claim full thread safety.  
**Resolve before:** SHARED-1 / WEAK-1.

<a id="q15"></a>
### Q15 — Inheritance, interfaces and runtime type information

**Question:** What inheritance/interface model is required, what is the override/cast contract, and which types require runtime descriptors or reflection?  
**Direction:** Native dispatch and metadata are pay-for-use. Unique lifetime does not prohibit interfaces; every class need not behave like GObject.  
**Resolve before:** DISPATCH-1 / INTERFACE-1; reflection remains separately scoped. [R1, §§11, 33]

<a id="q16"></a>
### Q16 — Lazy property state and failure

**Question:** What happens on recursive initialization, failed evaluation, destruction during use or concurrent first access? Is invalidation/reset supported, and how does a cached owner behave?  
**Direction:** First successful evaluation and later cached reads are the founding model. Final syntax, failure caching, reset and synchronization are not decided.  
**Resolve before:** LAZY-1; later owning/async lazy extensions. [R1, §19]

**Checkpoint 2026-10-04:** LAZY-1 remains near-term; future failed initialization may use the checked channel without changing cache/reentrancy rules here. Q16 stays OPEN. Contract/review.

**Bounded answer 2026-10-09:** The actual LAZY-1 starter approves first-success copied-value class caches, failure reset/retry after cleanup and fatal Evaluating reentry. [ADR 0093](decisions/0093-first-success-cached-properties.md) and [the language subset](language/properties.md#first-success-cached-properties) record that partial answer. Owning/text caches, async getters, invalidation and concurrent initialization remain outside this answer; Q16 remains open for those extensions. The accepted ASYNC-IO-1 L1 timer/cancellation results are preserved. All seven tracks and original Q01–Q35 text/IDs remain; PERF-01 is Candidate / not scheduled.

<a id="q17"></a>
### Q17 — Property value and ownership contracts

**Question:** Does each property return a copy, a borrow or a transferred owner, and how is that intent expressed? Can setters consume or replace state? Which stored/automatic forms are useful?  
**Direction:** Resource-valued properties are deferred, not permanently rejected. Preserve accessor effects; computed access is not implicitly lazy.  
**Resolve before:** PROP-LIFE-1 / PROP-COMPOSE-1; coordinate with TEXT-OWN-1.

<a id="q18"></a>
### Q18 — GObject/GIR identity and lifetime translation

**Question:** How are repeated conversions mapped to stable wrappers, and how are cross-boundary strong/weak references, callbacks, signals, cycles and threading handled? Which GIR import/export subset comes first?  
**Direction:** Foreign adapters, not native GObject semantics. Do not choose an identity table or header strategy without the lifetime contract.  
**Resolve before:** GOBJECT-1 / GIR-1. [R1, §§14–16]

## 6.4 Text, bytes and containers

<a id="q19"></a>
### Q19 — Owned text and borrowed substrings

**Question:** What owns generated UTF-8, what representation does a borrowed view retain, and how can results, fields and collections store each safely? Which substring operations preserve valid encoding?  
**Direction:** Preserve current text identity/invariants unless an explicit decision changes them. Byte length, scalar count and display graphemes are different quantities.  
**Resolve before:** TEXT-OWN-1 / TEXT-LIB-1.

**Q19A checkpoint 2026-10-15:** After the fresh baseline and explicit approval
of [ADR 0099 option 2](decisions/0099-validated-utf8-message-factory.md),
TEXT-OWN-1A implements the opt-in compiler-backed `utf8_message(u8[])` factory.
It strictly validates runtime bytes, then creates a concrete unique Class with
an independent counted snapshot and the existing receiver-bound string view.
Malformed UTF-8 uses ordinary checked InvalidUtf8; the nonnegative I32 count
bound and fatal OOM contract remain explicit. Native/O2, memory, phase mutation
and bounded regression evidence are in qualification.
This resolves finite Q19A byte ingress only. Q19's broader owned strings and
substrings, Q20 growth, Q21 external ingress/formatting and generic members
remain open. Existing concrete child storage works; no owning Class arrays or
general collection/generic storage is added.

**Q19B checkpoint 2026-10-16:** Approved [ADR 0102](decisions/0102-counted-utf8-byte-builder.md)
adds one source-level `Utf8ByteBuilder`, with separately approved lexical private
fields on ordinary nongeneric Classes. Counted raw fragments can split a scalar;
complete snapshots use Q19A and own independent immutable storage. Safe growth,
retry after truncation, cleanup and `Bag<Utf8Message>` integration are qualified
in TEXT-OWN-1B. Formatting, external byte I/O,
substrings and broader Q19/Q20/Q21 completion remain open.

<a id="q20"></a>
### Q20 — Collection growth and view invalidation

**Question:** What are length/capacity, growth, reserve and failure rules? When can elements relocate, how are move-only elements handled, and what invalidates an outstanding view?  
**Direction:** An owning array is not already a resizable container. No unsafe reallocation hidden beneath an apparently stable borrow.  
**Resolve before:** CONTAINER-1; coordinate with STRUCT-MOVE-1 and allocators.

**Finite Q20B checkpoint 2026-10-16:** Q20A's exact heap-Class slots now have
the separately approved bounded generic-Class source form. Reserve/append,
reverse cleanup and call-scoped loan rules retain the Q20A contract; instance
keys, members and element cleanup retain exact compile-time identity. This does
not add extraction, shrinking, persistent views, new allocation policy or general
generic containers. Q20 stays OPEN. [Guide](language/generic-class-bags.md),
[decision](decisions/0101-exact-class-generic-bag.md).

<a id="q21"></a>
### Q21 — External bytes, paths and formatting

**Question:** How do raw file/path bytes enter the language, where is UTF-8 validated, and what APIs parse/format numeric or structured text? Are formats checked at compile time?  
**Direction:** Text entry does not promise arbitrary OS-byte preservation. Keep binary input distinct; expose allocation and error policy. No silent locale conversion or mandatory formatting engine.  
**Resolve before:** BYTES-IO-1 / TEXT-LIB-1 / FORMAT-1.

## 6.5 Systems types, targets and optimization

<a id="q22"></a>
### Q22 — Wider integers, sizes and arithmetic modes

**Question:** Which fixed/pointer-sized names and conversions are needed? How do array lengths and foreign sizes migrate? Which checked and saturating operations remain to be added beyond current primitives?  
**Direction:** Existing `int`, exact conversions and wrapping semantics remain stable until explicitly superseded. Copying a target width into semantic identity is not a portability design.  
**Resolve before:** INT64-1 / SIZE-1 and relevant numerical extensions.

<a id="q23"></a>
### Q23 — Public optimized builds

**Question:** What optimization levels/pipelines become supported, with which target defaults, reproducibility and cost reporting? How are exact rounding, allocation failure, traps and observable calls preserved?  
**Direction:** Public optimization is missing despite internal optimized qualification. Profile compiler latency separately; do not invent unsafe global fast math to obtain a speedup.  
**Resolve before:** OPT-PIPELINE-1. [R2, S03]

<a id="q24"></a>
### Q24 — Broader C contracts and stable boundaries

**Question:** Which real APIs first require widths, typed buffers/pointers, structs/unions, out/in-out arguments, callbacks, constants/header expressions and retention? How are layout and native/foreign identity distinguished?  
**Direction:** Strongly typed explicit boundaries; C is permanent. No bitcast-based acceptance or assumption that matching pointer/width carriers prove the full contract.  
**Resolve before:** CABI-EXT-1 and affected adapter campaigns. [R1, §13]

**Checkpoint 2026-10-04:** Future enum/fallible NABI capabilities require separate versioned physical validation; native layout, C adaptation and serialization stay separate. Q24 stays OPEN. Contract/review.

<a id="q25"></a>
### Q25 — Allocator authority and lifetimes

**Question:** How is heap/arena/region/pool/static storage selected, and who retains the allocator or region? What allocation failure, alignment, destruction and escape rules apply?  
**Direction:** No mandatory global heap, hidden lifetime extension or undeclared runtime dependency. Construction and allocation policy must stay separable.  
**Resolve before:** ALLOCATOR-1; coordinate with objects, frames and containers. [R1, §§31–32]

**Checkpoint 2026-10-04:** No allocator/frame/provider policy is changed; allocation exhaustion remains fatal in the initial subset. Q25 stays OPEN. Contract/review.

<a id="q26"></a>
### Q26 — First embedded deployment and hardware access

**Question:** What exact target/board or execution environment comes first, and what backend, startup, linker, ABI and runtime work is required? Which MMIO, volatile, interrupt and atomic rules are necessary?  
**Direction:** Dreamcast/SH-4 remains a real architectural workload; easier host evidence cannot replace it. General multithreading is not established by cooperative async.  
**Resolve before:** DRIVER-TARGET-1 / EMBEDDED-1; before any claimed concurrency support.

<a id="q27"></a>
### Q27 — SIMD breadth and floating policies

**Question:** Which f64/wider vectors, alignment/load/store/reduction facilities are most useful? How are explicit fused or relaxed policies scoped and composed with strict defaults?  
**Direction:** Preserve current numerical guarantees and qualified primitives. Distinguish semantic operations from target-specific intrinsics and measured hardware support.  
**Resolve before:** SIMD-POLICY-1 and target expansion. [R1, §§26–30]

## 6.6 Projects, ergonomics and maturity

<a id="q28"></a>
### Q28 — Modules versus separate compilation

**Question:** What names, imports, visibility and dependency rules are needed? Later, how are generic bodies, native ABI versions and compiled interfaces distributed?  
**Direction:** One global multi-source program is the current model. Do not conflate namespaces, C object linkage, packages and independently compiled Astra modules.  
**Resolve before:** MODULE-1; a separately authorized compiled-unit campaign.

<a id="q29"></a>
### Q29 — Tooling and diagnostic provenance

**Question:** Which formatter/editor/debugger capabilities are required first? How are optimized source locations and embedded caller snippets handled, including path/privacy controls?  
**Direction:** Inspect current external tooling before duplicating it. Source-aware diagnostics are useful but neither a debugger nor a privacy scrubber.  
**Resolve before:** TOOLS-1 and relevant public optimization/debug features.

<a id="q30"></a>
### Q30 — Named alternatives and control-flow convenience

**Question:** What enum/alternative representation and selection/exhaustiveness rules are appropriate? Which counted-loop/iteration constructs should arrive first, and how do they preserve cleanup and borrow scopes?  
**Direction:** Remove routine boilerplate without importing a large interacting type system. Coordinate alternatives with ERROR-1 rather than preselecting its representation.  
**Resolve before:** ENUM-1 / CONTROL-1.

**Checkpoint 2026-10-04:** Direction USER_APPROVED: nominal type-safe payload enums with exhaustive matching and payload-derived ownership. D01–D05 remain PROPOSED; iteration/control extensions are unchanged and Q30 stays OPEN. Contract/review.

<a id="q31"></a>
### Q31 — Comparison-chain semantics

**Question:** Which comparison operators may chain, how are shared operands captured once, and when are later operands skipped? What happens for mixed types, NaNs or vector results?  
**Direction:** A strong readability candidate; binary comparisons retain their behavior, and exact scalar chains have the separately qualified ADR 0122 contract. No implicit numeric promotion or mask-to-bool reduction follows from chaining.
**Resolve before:** COMPARE-CHAIN-1. [R2, S11]

<a id="q32"></a>
### Q32 — `with` name resolution and receiver identity

**Question:** Do members require a leading dot, how are lexical conflicts diagnosed, and does the receiver refer to original storage or a temporary value? What prevents invalidating its owner during the block?  
**Direction:** Evaluate the receiver once and keep storage/lifetime meaning clear. The previously suggested leading-dot form is not approved syntax.  
**Current bounded implementation:** [explicit qualified with captures](decisions/0126-explicit-qualified-with-captures.md). Leading-dot lookup, escaping aliases and mutating captured receivers remain excluded. [R9]

<a id="q33"></a>
### Q33 — Regex dialect and runtime cost

**Question:** Which literal grammar, flags and regex dialect are supported? Are constant patterns validated or compiled ahead of time, and what are construction, reuse, allocation and JIT costs?  
**Direction:** Optional text capability; unused programs acquire no regex runtime. Literal convenience must not silently select an engine or mandatory JIT.  
**Resolve before:** REGEX-1. [R9]

<a id="q34"></a>
### Q34 — Remaining inference and immutable bindings

**Question:** Which unresolved-generic locals can safely infer their exact type, and is a separate runtime immutable-binding facility needed? What aggregate constants or compile-time execution, if any, are justified?  
**Direction:** `var` and concise `const` are canonical; current `const` is compile-time. Do not introduce `let`, `readonly`, CTFE or aggregate constants by implication.  
**Resolve before:** Any dedicated inference/immutability/compile-time extension.

**Checkpoint 2026-10-04:** Concrete var infers a complete constructor/capture type; generic constructor arguments remain explicit and unresolved generic local inference is unchanged. Q34 stays OPEN. Contract/review.

<a id="q35"></a>
### Q35 — Release scope, bootstrap and performance claims

**Question:** Which readiness gates define the first public release, which targets/ABIs are promised, and when does Stage 1/Stage 2 self-hosting begin? What benchmarks and safety claims are supportable?  
**Direction:** A useful release need not implement every future feature. Preserve provenance/name review and selected licensing; do not resurrect the historical undecided compiler-license question.  
**Resolve before:** Release planning / SELFHOST-1. [R1, §§1, 8, 47] [R2, S12]

# 7. Roadmap adherence and change control

## 7.1 Default: stay on the path

Before each submission, identify the latest accepted commit, the roadmap version, the next campaign’s track and the open decisions it will close. Explain how its acceptance advances the vision in ordinary source. The default is the next agreed item or a ready item from a coordinated track—not another speculative prerequisite or an unrequested optimization series.

A concrete correctness failure, required dependency, unavailable input or measured operational limit can justify a detour. Record the exact blocker and the smallest bounded repair/contract campaign needed, together with the campaign to resume afterward. A semantic policy change, major reordering or new feature family needs an explicit decision before implementation. Planning labels may be refined without pretending the underlying commitment disappeared.

## 7.2 A short change record is enough

For each material departure, record the milestone/question, evidence, alternatives, approved decision, dependency/scope changes and return point. Update the revision and preserve historical outcomes.

After acceptance, record the exact receipt, delivered scope, limitations, closed questions and next campaign. Each resolved question needs an ADR/decision reference. Preparation or a positive reduced example alone does not establish delivery.

## 7.3 Qualification proportional to the change

Preserve strict semantics, independent stage/ABI checks, numerical evidence and lifetime tests. Scale qualification to risk: focused checks for documentation/tooling, appropriate regression for semantic changes, and full application/target acceptance at meaningful closures. Do not automatically rebuild two full suites for an observational edit when verified receipts and targeted equivalence suffice. Preserve “semantic guardrails, not ceremonial drag.” [R1, §§39–42] [R7]

Separate normal returns, intentional fatal behavior, inherited limitations, preliminary failures and reused receipts. The reported 49,152-byte inherited GLib loss remains a specifically bounded compiler control, not a blanket allowance for new leaks or a reason to claim all measurements are zero-loss. Preserve raw evidence needed to support the actual claim. [R3]

## 7.4 Keep evidence useful and storage bounded

Maintain a usable current build, source/toolchain identities, commands, receipts, selected observations and minimized failures. Isolate scratch paths; do not retain a full build/archive per sample or edit.

Honor the latest authorized cleanup ledger. Reproducible source is not a retained executable. Protect surviving user work, stashes, peers and private assets; space pressure does not authorize historical deletion or resurrect obsolete retention requirements. The reported final 5.87 GB build size is a historical observation, not a quota or current disk reading. [R3] [R4]

## 7.5 Documentation reconciliation is immediate maintenance

DOCS-SYNC-1 adopts this v1.1 master and reconciles the audited object/generic claims, syntax guide and configured milestone label against current source and later qualification. The [documentation index](README.md), [capability matrix](language/capabilities.md) and reconciliation ledger connect them. Historical reports and expectations remain unchanged. The configured banner identifies OWN-SWAP-1 as the latest language feature, separately from newer profiling/documentation deliveries. Repository completion is recorded externally; user acceptance remains pending here. [R2, S12] [R11]

# 8. Revision policy and working record

## 8.1 The next decision

Review the [shared enum/error contract](architecture/enums-and-errors.md) and nine concrete recommendations, then prepare ENUM-1 under the bounded implementation exits. CALLABLE-1/V01–V03 are preserved as delivered internal foundations. The revised A+C ASYNC-1 is the required return point after ENUM-OWN-1 and ERROR-1; no production implementation is authorized by this design/model checkpoint. LAZY-1 stays near-term; PERF-01 stays Candidate / not scheduled. Earlier preparation and qualification records retain their historical scope.

This preserves the preceding roadmap’s direction. It does not preapprove an error syntax, task runtime, nullable-type spelling, shared-class grammar or a regex engine. Those decisions remain in section 6 until deliberately closed.

<a id="async-contract-1-r2"></a>
### ASYNC-CONTRACT-1 R2 direction addendum — 2026-10-03

**User-approved platform direction:** use appropriate native Linux kernel
facilities through an explicit native boundary; GLib is not the native scheduler,
I/O authority or fallback. Derive a precise hard dependency from required
behavior/fixes, including an upstream RC when justified. Missing or denied
required capabilities fail explicitly. Portable Task/Frame/Executor semantics
and an application-owned bounded manual pump remain design requirements; no
mandatory process-global executor or invisible default-runtime linking is selected.

Provenance is the user's 2026-10-03 platform messages retained in the verified
ASTRA-ASYNC-CONTRACT-1-R2 packet, plus the explicit revision-2 continuation
instruction. The [Proposed ADR 0085](decisions/0085-native-async-contract.md)
records this bounded policy delta. It authorizes no kernel/package/security
mutation or production async implementation.

The R2 review now supplies coherent proposed
answers and a bounded lifecycle model for Q01–Q06. The selected
[Linux profile](platform/linux-async-profile.md), its precise proposed floor and
all source/task/lifetime choices remain **PROPOSED / USER REVIEW REQUIRED**.
This supplements the preparation handoff; it does not close Q01–Q06 or Q12/Q16/Q25.
All Q01–Q35 text/IDs and seven tracks are preserved. CALLABLE-1/ASYNC-1 have not
started; LAZY-1 remains near-term and PERF-01 Candidate / not scheduled. Native
runtime/provider qualification remains a later explicit gate.

<a id="enum-error-contract-1"></a>
### ENUM-ERROR-CONTRACT-1 bounded direction amendment — 2026-10-04

**User-approved change:** use nominal type-safe payload tagged unions and the
same value/ownership foundation for ordinary structured errors; retain explicit
outcome inspection and add concise word-based propagation (A+C). Establish
checked synchronous errors before source async. The approved direction is not
approval of all grammar, handler, generic storage or ABI details in the
[Proposed ADR 0087](decisions/0087-shared-enum-and-error-foundations.md).

**Reason:** ordinary application code should inspect outcomes when policy matters
and propagate routine failure concisely. A scalar-only private async error or
explicit-matching-only first usable surface would contradict that shared target.
The old unexecuted A1-R3-EXPLICIT draft is superseded as a plan, never accepted
as an implementation order; its historical bytes and R3 lifecycle proofs remain.

**Immediate finite sequence and exits:** ENUM-1 delivers useful payload enums and
native value/match/validity witnesses; ENUM-OWN-1 must qualify BufferState and
parameterized scalar/record/void/owned-buffer outcomes before ERROR-1 depends on
them; ERROR-1 delivers capture/try/handlers and real error-edge owner cleanup;
return to Track A for revised ASYNC-1 with the same foundation and A+C, then
ASYNC-IO-1 for provider qualification. The exact matrix
permits combining ENUM-OWN-1 into ENUM-1 only if all its exits are qualified.
General owning structs/containers, text, closures and all generic categories are
not extra default prerequisites. No further abstract enum/error survey is needed.

**Preserved boundaries:** CALLABLE/V01–V03, parent-only cancellation, pending
single-observer rights, observed target/release/command barriers, retirement and
stable frame/code/environment association; native-kernel-first policy; seven
tracks and unchanged Q01–Q35 wording. Q05/Q30 have linked proposed answers,
not closure. Q10/Q11/Q13/Q16/Q24/Q25/Q34 coordination is limited above.
LAZY-1 is near-term and PERF-01 Candidate / not scheduled. No production enum,
checked error, async syntax, provider, runtime unwinder or new ABI is implemented.

## 8.2 Revision log

### ENUM-OWN-1 coordination ledger — 2026-10-06

Pierre-Marc explicitly approved `E2-OWNED-GENERIC-SUMS` in an actual message;
[ADR 0089](decisions/0089-owning-generic-enums.md) records that bounded source
scope. Ordinary scalar/record/void/array outcomes now share generic enum machinery,
with readonly inspection, whole transfers and active cleanup. The implementation
is submitted with qualification PARTIAL: the required
complete final strict suites and the full independent forgery matrix remain open.
The all-target build exceeded the live 8 GiB managed-output guard and was stopped.

Enum-containing structs/classes and enum collections are explicitly deferred;
copyable records remain eligible payloads. This does not implement general owning
structs or broaden plain-T owner admission. D06/D07/D09, checked-error source
policy and async choices remain proposed; Q01–Q35 and all seven tracks are
unchanged. The next source gate remains ERROR-1 approval after E2 qualification
review, then revised A+C ASYNC-1 and real ASYNC-IO-1. The old explicit-only async
packet is not an implementation order. LAZY-1 remains near-term and PERF-01
Candidate / not scheduled. No Linux provider or executor starts here.

**Version 1.0 — 2026-09-27.** Consolidates the vision, amendments, source findings, milestone tracks, 35 open questions and adherence rules. Accepted baseline: OWN-SWAP-1. COMPILE-PROFILE-1 remains Submitted. No implementation or repository change.

**Version 1.1 — 2026-10-03, DOCS-SYNC-1; acceptance pending.** Imports the approved
v1.0 master and source audit byte-for-byte; updates repository/language/suite
status, adopts current capability/navigation and reconciliation links, closes
COMPILE-PROFILE-1 as accepted measurement, records PERF-01 as Candidate / not
scheduled, and prepares the ASYNC-CONTRACT-1 handoff. The single configured label
correction identifies OWN-SWAP-1. Sections 1, the seven track bodies, readiness
gates, Q01–Q35 text and change-control rules retain their direction. All 35
questions remain OPEN; no new semantic ADR or language contract is approved.
Exact revision operations and preservation checks are in the evidence. [R11]

**Version 1.1 addendum — 2026-10-03, ASYNC-CONTRACT-1 R2.** Adds the dated
user-approved native-platform direction and links reviewable design/model/profile
proposals. The original v1.0 snapshot and v1.1 log above remain intact; no open
question or implementation status is promoted by model PASS.

**Version 1.2 — 2026-10-04, ENUM-ERROR-CONTRACT-1.** Records the user-approved
shared variant/error and A+C direction plus bounded error-before-async reorder.
Updates immediate priorities/navigation, adds nine question coordination notes
without altering original question/track wording, and links one Proposed contract,
ADR, review table and finite implementation exits. Detailed source/ABI approval
is PENDING; model qualification is separate from semantic acceptance. Original
v1.0 history, v1.1/R2 records and R3 model/reports are unchanged.

Future revisions should state which accepted milestone or explicit design decision caused the change. Retain stable question IDs and a short supersession note. Revise priorities when evidence warrants it, but explain the change rather than quietly replacing the path.

---

**Working commitment:** build the language we actually want, keep current facts separate from future promises, and make every justified detour lead back to that path.

# Interop/Async Surge-5 checkpoint — 2026-10-17

The current coverage matrix and
qualification add bounded single-threaded C
retention with observed quiescence, real Linux file payload suspension and
cancellation, GNU x86-64 SysV LP64 by-value numeric records, and checked native
closures. Eight new public applications A33–A40 exercise those boundaries.
These are implementation/qualification additions to Q01–Q06, Q21–Q24; the
original questions and seven track bodies retain their meaning and open scope.

The next broad campaign should address property/lazy completion together with
allocator policy and richer generic/aggregate composition, using real object
and text applications. Strict historical LAZY Q4 remains HELD; it requires its
own explicit continuation. GObject/GIR, module/debug workflow, everyday control
syntax, target/SH-4 and wider SIMD remain missing families. Self-hosting remains
deferred until most Founding Bible features exist and the user authorizes it.
Surge-3's PARTIAL result and earlier acceptance records are preserved.

# 9. Sources and provenance

The bracketed references retain their historical provenance. R1 and R7 are named historical references absent from the packet; their full contents were not reverified and no accessible link is invented. The PDF is likewise a named v1.0 historical reading artifact. The imported source audit preserves original excerpts, line numbers, hashes and snapshot qualification; current source/decision/test links are in the [capability matrix](language/capabilities.md). Existing local links below point only to retained files. The future tracks and open-question alternatives are planning synthesis from these materials and the project discussion; they are not external research or executed results.

<a id="ref-r1"></a>
**[R1] Founding Bible, with amendments.** `ASTRA_FOUNDING_BIBLE_2026-09-13.md`, 2,170 lines. Sections 0–63 establish the architecture; sections 64–68 record human/AI reviewability, inference, ownership and struct-value amendments. Snapshot SHA-256: `32ab9a23679b98cd2dc56bb93f2a47386be63cc3e2fbb0deb6cae1f019922246`.

<a id="ref-r2"></a>
**[R2] Source audit and uploaded code.** `ASTRA_ROADMAP_SOURCE_AUDIT.md`, sections S01–S12, SHA-256 `f1e9a36d66486d70d4d3d2b0b1d74520ed27b26e9b245f61885737c0fd0a5e46`. Audited archive: `astra.tar.xz`, SHA-256 `94fbb06549f3953c84796163e947e6d846e6cbf8d7018e974e36c1237c2b64c3`. This is static inspection, not a compiler rebuild. Archive/package identity limits are stated in section 3.1.

<a id="ref-r3"></a>
**[R3] OWN-SWAP-1 qualification.** OWN-SWAP-1 validation; accepted source/runtime/ownership/application scope, benchmark limitations, memory categories and cleanup history. Supplied report SHA-256: `1cb8d0866a5e764958e72324b474e6253563837748ac4d45b76224a388bf2d82`.

<a id="ref-r4"></a>
**[R4] OWN-SWAP-1 final delivery.** retained OWN-SWAP-1 final state, recorded 2026-09-27. Commit `ca7c2301c60f92185e1c8689b3d41f470ee92b0f`, tree `09f6ba544ea3a30a764cf30d644dd08b5a23ddcb`, one commit and clean worktree. The reported Git delivery archive is distinct from the uploaded inspection package.

<a id="ref-r5"></a>
**[R5] Complete CAD application checkpoint.** APP-CAD-2 validation and its [workload/source map](workloads/cad-idiomatic.md). Full native-state I0 qualification and original L/P/I distinctions. Supplied report SHA-256: `84804e518ae59e16725cdbd814f7f096e2412267d9b63189a6ee4c6a68cda308`. OWN-SWAP supplies the later I1 extension; older blocked checkpoints remain historical.

<a id="ref-r6"></a>
**[R6] Generic values and collections.** `docs/gen-copy-1-validation.md`, `docs/gen-slice-1-validation.md`, `docs/gen-buffer-1-validation.md`, and corresponding current language/IR guides inspected in R2. Read each milestone in sequence: later accepted capabilities supersede earlier bounded exclusions without changing the older report’s historical result.

<a id="ref-r7"></a>
**[R7] Historical submitted observational campaign.** `ASTRA-COMPILE-PROFILE-1-SUBMISSION.md`, SHA-256 `270f55e376b10229d7d93185aa49814d5329ddd200d6f36a5b49672fb32fb286`. This is a submission, not a completed profiling report or optimization decision.

<a id="ref-r8"></a>
**[R8] Existing failure and text boundaries.** `docs/alloc-fail-1-validation.md`, `docs/text-1-validation.md`, `docs/text-io-1-validation.md`, `docs/args-1-validation.md`, `docs/diag-1-validation.md`, and the current guides excerpted in R2. These distinguish fatal actions, borrowed/static text, argument capture and assertions from future recovery/owned-text features.

<a id="ref-r9"></a>
**[R9] Project discussion and adoption.** The conversation’s human/AI vision, inference and implicit-borrow amendments; unique/shared/weak and value-semantics discussion; rejected Jai declaration direction; Vala-inspired comparison/nullability/with/regex candidates; the preceding source-based roadmap; and the request to make this a maintained Markdown/PDF planning reference. Candidate syntax is preserved as unresolved, not silently ratified.

<a id="ref-r10"></a>
**[R10] Accepted COMPILE-PROFILE-1 measurement.** [Study](compiler/latency-study.md),
SHA-256 `2d497a3c48ef0b720d1f3cf56d3081a8e969cbd3d085fcc5c44818c09947173c`;
validation, SHA-256
`fd2348e85c7ba3d68834f8073954e281d501082ee66bf4d193049b5118673165`;
retained final receipt, SHA-256
`3d1feb17ff5834479542a37cbd068defc9a55af72f8150565477083542351cf2`.
Accepted repository delivery `9a8d393b7e7add7b8a5c1233785c3ea9f46d5a0a`;
measurement acceptance does not authorize its recommended optimization campaign.

<a id="ref-r11"></a>
**[R11] DOCS-SYNC-1 adoption and qualification.** Validation,
files and evidence.
Supplied instruction ASTRA-DOCS-SYNC-1, preparation date 2026-09-28, authorizes
this maintenance; repository completion is separate from user acceptance.
The packet manifest and all seven members were verified before import. The
[historical master](history/ASTRA_VISION_AND_ROADMAP_v1.0_2026-09-27.md) is
SHA-256 `a5da459415e76fa8233f52cde13acb34b84528703f607b4e53cd6ded50edd832`.
No final self-referential commit hash is embedded in these files.

## 2026-10-03: CALLABLE-1 internal implementation ledger

CALLABLE-1 qualification records the bounded generated
continuation foundation under [ADR 0086](decisions/0086-internal-continuations.md)
and the [internal contract](ir/internal-continuations.md). It implements Q06's
minimum internal realization only. All seven tracks and Q01–Q35 questions retain
their wording and open decisions. ADR 0085 remains Proposed. Async source, Task
scheduling, Completion/error propagation, suspension loans and the Linux/liburing
provider profile require their next explicit approval. LAZY-1 remains near-term;
PERF-01 remains Candidate / not scheduled. Native-kernel-first direction remains.


<a id="error-1-native-exceptions"></a>
## ERROR-1 native-exception direction, 2026-10-07

The actually submitted user direction approves native class exceptions and Error.message, superseding the unapproved enum-backed E3 draft and inconsistent explicit-only/A+C-mandatory async proposals. [ADR 0090](decisions/0090-native-exceptions.md) records the contract; implementation scope remains PARTIAL. Enum and Result values remain separate. Revised exception-based async follows ERROR-1 acceptance and is not implemented here.

All seven tracks and original Q01–Q35 questions/IDs above remain unchanged. The following disposition notes amend earlier direction without closing the broader questions.

| Question | Current disposition |
| --- | --- |
| Q05 | Approved class-based synchronous exceptions; checked subtype bounds and ordinary message property. General async/cancellation behavior remains open. |
| Q07 | Bounded explicit unique heap construction is implemented as an ERROR-1 prerequisite; general factories/ownership policy remains open. |
| Q10 | Enum ownership remains ordinary; no general move-only record/partial-state extension. |
| Q12 | Heap and lexical/caller storage authority remain distinct; existing null/fatal rules persist. General refinement remains open. |
| Q15 | Bounded single inheritance and virtual dispatch are prerequisites; interfaces and reflection remain open. |
| Q17 | Get-only message/snapshot properties have receiver/static lifetime and a nonthrowing pure subset; general property lifetime/loan contracts remain open. |
| Q19 | Immutable counted Class snapshots and Q19A validated byte-to-message construction are implemented; general TEXT-OWN-1/substrings remain open. |
| Q24 | A private native channel requires explicit nonthrowing C adaptation; no C unwind or new stable foreign exception ABI. |
| Q25 | Existing fatal allocation exhaustion persists; no allocator/frame/provider policy is selected. |

### ERROR-1-R1 bounded completion, 2026-10-07

The successor implements exact stored receiver/message loans, distinct heap
factory/parameter/result authority, fresh acquisition abort, checked owner
forwarding and result-mediated rearm. R1 validation
separates the finite native/proof witnesses from final strict qualification.
The original ERROR-1 PARTIAL receipts remain historical; final disposition is
in the current report. All seven tracks and Q01–Q35 remain intact. The approved
exception direction remains unchanged; async, Linux provider, reflection, shared
ownership, formatting and performance work are outside this completion.

### ASYNC-1 approved native task subset, 2026-10-08

ERROR-1 is accepted on independent source/receipt reconstruction and supplied
native evidence. Its candidate 9,137 and independent composite 8,601 + 536 remain
separate, with the explicitly approved Python 3.14.7 → 3.14.8 change and original
interruptions disclosed. The continuation changed no source or frozen product.

The live user approved A2-NATIVE-EXCEPTION-TASKS: deferred unique tasks, ordinary
await with native exceptions, separate cancellation, explicit start/join,
bounded suspension loans/frames and an explicit virtual executor/void-root
bridge. [ADR 0091](decisions/0091-native-exception-tasks.md) records that approval.
[Current source scope](language/async.md) and finite controls
remain PARTIAL; full first-subset acceptance is pending. Q05 has this approved
bounded async direction while its broader questions remain open. All seven
tracks and original Q01–Q35 text/IDs are preserved. Real Linux ASYNC-IO-1 is a
separate subsequent gate. LAZY-1 stays near-term; PERF-01 stays Candidate / not
scheduled.


**Language-usability successor checkpoint:** U1–U7 evidence and current Q01–Q35 map record scoped for/readonly Bag foreach, explicit nonnull, scalar chains, qualified with, hosted floating text and the TAB formatter. A49–A56 are fresh eight-app evidence, not a full rerun of earlier 48. Historical strict LAZY-1 Q4 remains HELD/INCOMPLETE; self-hosting stays deferred.


### Surge 12 finite allocation and no-OS successor

The [allocation/target contract](language/allocation-policies.md),
[A97–A108 corpus](../examples/freestanding-allocation-12/README.md), and
current Q01–Q35/Bible map record checked
policy admission, original owner/release authority, selected natural POD layout,
and actual approved non-SH-4 no-OS execution. The
working ledger and final evidence keep
the exact qualification revision and scope.

Bounded domains initially have static backing lifetime. Fallible construction
initially takes synchronous unmanaged scalar inputs. Nondefault Closure storage
supplies the selected execution-family gate; general frame placement remains
separate. The emulator's fixed atomic word and trap ABI do not accept the
threading/networking surge or qualify physical silicon. Historical LAZY-1 Q4
remains HELD/INCOMPLETE. Broader threading, foreign/native exports, resolver,
release registry and self-hosting boundaries remain as recorded above.
