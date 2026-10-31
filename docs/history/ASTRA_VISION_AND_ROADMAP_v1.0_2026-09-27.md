# ASTRA

## Vision, Roadmap & Open Decisions

**Version 1.0 · 27 September 2026**  
**Planning reference for Pierre-Marc Jobin and Asteria**  
**Accepted implementation baseline:** OWN-SWAP-1, `ca7c2301c60f92185e1c8689b3d41f470ee92b0f`  
**Current submitted campaign:** COMPILE-PROFILE-1 — completion not yet reported.

> Make sophisticated systems programming look ordinary. Preserve meaningful cost and danger; remove redundant ceremony.

This document consolidates the founding vision, subsequent amendments, the source-based roadmap review and the instruction to follow that path closely. It is the working planning reference for subsequent submissions. It is not a claim that planned features exist, nor a blanket authorization to resolve every open language-design question during implementation. The Markdown is the editable master; the PDF is the matching reading snapshot.

No compiler build or test campaign was rerun to produce this document. Implementation status comes from the supplied qualification records and static source audit. The uploaded source package is identified separately from the accepted Git delivery. [R2] [R3] [R4]

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

Only COMPILE-PROFILE-1 is currently **Submitted**. Future campaign labels below are planning handles, not reserved ADR numbers or promises of one commit’s implementation scope. A group may be split when that materially reduces risk. No calendar dates or completion percentages are assigned.

## 2.2 Distinguish current contracts from future intentions

Current code and its latest applicable qualification establish what the accepted compiler does. The founding Bible and this roadmap establish what we intend to build. A future intention does not silently change an existing contract. Conversely, an old temporary restriction is not a permanent design veto.

When documentation conflicts, record the conflict, inspect the current implementation and applicable later decision, then reconcile the living guide explicitly. Preserve historical reports as historical evidence. In particular, this document does not revive obsolete source restrictions or claim that deleted build artifacts still exist. [R2, S12] [R3]

Open questions in section 6 elaborate the unresolved areas already identified by the vision and roadmap. Their alternatives are discussion prompts, **not newly approved semantics**. A question is closed only by an explicit decision, recorded rationale and the appropriate qualification—not by an example that happens to use one spelling.

# 3. Where Astra stands now

## 3.1 Accepted baseline and evidence limits

OWN-SWAP-1 is the latest accepted delivery: one clean commit on `astra-own-swap-1`, identified above. Its two fresh strict builds each passed 9,099 tests. CAD I1 passed the original 13 acceptance entries, 37 controls and 20,560 retained exact native observations. This document relies on those reports; it does not claim an independent rerun. [R3] [R4]

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

The domains and restrictions above come from the inspected source, not from extrapolating milestone names. Generic specialization becomes existing concrete operations before CFG; arrays are not automatically admissible as plain generic `T`, and read-only deep-borrowed `string[]` is not a mutable generic numeric/record slice. [R2, S01–S10] [R6]

## 3.3 Three distinctions that must remain visible

**A native backend is not yet a public optimized toolchain.** The inspected driver has no ordinary optimization selection, object-only, target or source-debug option. It creates the target machine with `CodeGenOptLevel.NONE`; the normal route does not run an LLVM IR optimizer pipeline. Internal O2/FMA test harnesses do not change that public status. Compiler latency, generated-program optimization and deployment tooling are separate campaigns. [R2, S03]

**Value copying is substantially complete; resource-bearing values are not.** Plain records need no `SimpleType` marker and can cross generic/native boundaries. A future record containing owned resources must derive different move and cleanup behavior. Current copyability does not imply equality, ordering or default construction. [R1, §67] [R2, S07] [R6]

**The CAD result is strong but scoped.** The native-state port preserved the retained numerical contract and improved CLI medians in two matched cases, while compilation and code size increased. The later owner swap removes payload rotation, but establishes no clear whole-CLI timing gain. Neither result proves universal performance parity or readiness for every application class. [R3] [R5]

# 4. Execution path and upcoming milestones

## 4.1 Immediate priorities

The default path is to finish the bounded compiler-latency study, reconcile current documentation, and move into native async/callable work while bringing lazy properties back into near-term scope. Owned application data and a public systems toolchain must advance as coordinated tracks, not wait until every desktop feature is complete.

| Order / position | Campaign | Intended outcome |
| --- | --- | --- |
| Current | **COMPILE-PROFILE-1 — Submitted** | Attribute compilation latency using equivalent instrumented/uninstrumented routes. Investigate at most one measured hotspot; “no actionable bottleneck” is a legitimate result. |
| Immediate housekeeping | **DOCS-SYNC-1 — Planned label** | Reconcile the live capability matrix, stale restrictions and milestone label. Adopt this roadmap in project documentation through a separate authorized edit. |
| Next major design | **ASYNC-CONTRACT-1 — Planned** | Freeze the minimum frame/task, suspension-borrow, completion/cancellation, error and executor contracts needed for a first implementation. |
| Early foundation | **CALLABLE-1 — Planned** | Establish a bounded callable/environment lifetime model and the callback capability actually needed by the selected executor/use case. |
| First async delivery | **ASYNC-1 — Planned** | Implement and qualify real suspension/resumption with a minimal cooperative executor. |
| Application closure | **ASYNC-IO-1 — Planned** | Execute a real asynchronous operation and an event-driven application, not only a synthetic state machine. |
| Near-term companion | **LAZY-1 — Planned** | Implement first-read evaluation/cache semantics with explicit lifecycle, failure and reentrancy rules. |

This is a priority order, not an assertion that every full callable/closure or object feature is a hard prerequisite for async. ASYNC-CONTRACT-1 must identify the smallest sufficient foundation. It must not expand into a requirement to finish shared ownership, reflection, all threading or a package system first. Error behavior should be coordinated with ERROR-1 early, even when its first implementation is deliberately narrow. [R1, §§19, 24–25, 34] [R7]

## 4.2 Track A — Async, callables and lazy evaluation

**Purpose:** deliver the founding language features that the numerical checkpoint did not exercise.

CALLABLE-1 must preserve a function together with any environment and lifetime/destruction responsibility. A native closure is not just an untyped C function pointer. ASYNC-1 must account for owners and borrows that remain live while execution is suspended, and for every permitted completion or cancellation path. Optional event-loop adapters must not define the native task ABI. [R1, §§24–25]

The preferred first scope is cooperative and single-threaded, with explicit executor ownership. Threaded execution remains a later qualified extension. A test executor is useful, but ASYNC-IO-1 closes the usability loop with actual external completion or timing. The exact operation, application and task syntax remain decisions in Q01–Q06.

LAZY-1 should begin with a bounded value/lifetime domain that the compiler can prove sound, while documenting how later owning values will compose. A successful getter is not enough: recursive first access, failed initialization and destruction of cached state need explicit behavior. Ownership-aware property expansion may follow without blocking a simple initial lazy capability.

**Closure evidence:** source examples with ordinary control flow; deterministic owner/frame/cache cleanup; rejected invalid borrows; real resumed execution; independent stage/ABI checks; and measured dependencies. No implicit claim of general concurrency safety. **Open decisions:** Q01–Q06, Q16.

## 4.3 Track B — Complete owned application data

**Purpose:** let an abstraction own its natural state rather than forcing callers to coordinate it manually.

| Campaign | Bounded objective | Dependency or scope boundary |
| --- | --- | --- |
| **OBJ-ALLOC-1** | Stable, independently allocated unique objects, alongside existing lexical/caller storage. | Select construction/storage/failure policy; do not make every object require a heap. |
| **OBJ-FIELD-2** | Parents owning child objects with transitive lifetime and safe replacement. | Build on the chosen object ownership/storage contract. |
| **STRUCT-MOVE-1** | Ownership-bearing struct fields with derived move-only transport and recursive cleanup. | Preserve plain copyable records; resolve partial-move and initialization rules. |
| **GEN-BORROW-1** | Non-consuming generic access to ownership-bearing values. | Preserve implicit-borrow ergonomics without changing plain value `T` into a reference. |
| **GEN-OWN-2** | Remaining direct generic owner-local and composition facilities. | Reuse ownership authority rather than create a second generic lifetime system. |
| **GEN-MEMBER-1** | Useful generic type/member abstractions, including required generic class/method forms. | Scope from real container/application requirements. |
| **CONTAINER-1** | A reusable owning collection with capacity/growth and explicit view invalidation. | Requires adequate owning state; not merely an unchecked `realloc` wrapper. |

These are planned additions, not claims that current `Box<T>` is a heap box or a generic owning class. The source still rejects generic classes/members and owned struct fields, and restricts direct generic owner locals and borrowing. [R2, S04, S07]

A collection’s growth policy, allocation failure and element movement must be visible enough to review. Type declarations should supply common policy where appropriate; individual uses should not restate derivable copy/move/cleanup properties. General extraction from an owned field remains a separate decision: the accepted buffer `swap` solves bounded exchange without approving arbitrary temporary field holes. [R1, §§66–68] [R3]

**Closure evidence:** a real owning abstraction; moves/replacement/normal errors; dependent-view rejection; no duplicated cleanup; and costs of growth/copying. **Open decisions:** Q07–Q12, Q19–Q20.

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

## 4.8 Track G — Readability and safe-default candidates

**Purpose:** retain the later Vala-inspired ideas without falsely marking their exact semantics as decided.

| Planning handle | Direction | Current status |
| --- | --- | --- |
| **COMPARE-CHAIN-1** | Mathematical comparison chains with once-only shared operands and defined short-circuiting. | Strong core-language candidate; not current binary-comparison behavior. |
| **NULLABILITY-1** | Evaluate non-null-by-default references and explicit nullable forms with flow refinement. | Important safe-default candidate; current nullable contracts require an intentional compatibility decision. |
| **WITH-1** | Group receiver operations without repeated long access paths. | Candidate; shadowing, original storage versus copy, and spelling remain open. |
| **REGEX-1** | Optional pattern literals and a well-specified matching component. | Candidate after basic text facilities; no mandatory regex engine or JIT. |

These labels organize the earlier discussion; they do not authorize syntax already rejected by the current parser. The suggested leading-dot `with` spelling and `shared class` spelling remain proposals. Jai-style `:=` declarations were not adopted; familiar `var` and typed declarations remain the direction. [R2, S11] [R9]

Small readability campaigns may be interleaved when their contracts are ready. They should not displace the major founding features indefinitely, nor be dismissed indefinitely as “only syntax.” **Open decisions:** Q12, Q30–Q34.

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

### Q01 — Async source and task meaning

**Question:** What are the native declaration and suspension spellings, and what value does calling an async function produce? Does it begin immediately or require scheduling? Can a result be awaited more than once?  
**Direction:** Native state machine/frame/executor; readable surface. Neither Vala-style `yield` nor `await` spelling is frozen here.  
**Resolve before:** ASYNC-CONTRACT-1 / ASYNC-1. [R1, §25]

### Q02 — Task completion, cancellation and abandonment

**Question:** Who owns a task, what happens when its owner disappears, and when is cancellation complete? Which code runs for success, error, cancellation and unobserved completion?  
**Direction:** Explicit ownership and deterministic permitted cleanup; no accidental detached work or retroactive promise of unwinding.  
**Resolve before:** ASYNC-CONTRACT-1; qualify in ASYNC-1 and ASYNC-IO-1.

### Q03 — Borrows across suspension

**Question:** Which references/views may remain live across a suspension, and how is backing lifetime proven? What invalidates a field or nullability refinement? What changes when a task can migrate between executors or threads?  
**Direction:** Ordinary synchronous noescape proofs are not automatically suspension proofs. Start conservatively without pervasive lifetime punctuation.  
**Resolve before:** ASYNC-CONTRACT-1; any later threaded extension.

### Q04 — Frame storage and executor boundary

**Question:** When are frames stack-, caller-, pool- or heap-backed? Who releases them, what allocation failures mean, and what minimal wake/completion protocol the first executor needs?  
**Direction:** Pay only for required storage; preserve a route to embedded/custom executors. Full shared ownership and a large runtime are not prerequisites.  
**Resolve before:** ASYNC-CONTRACT-1 / ASYNC-1; coordinate with ALLOCATOR-1.

### Q05 — Errors across ordinary and asynchronous calls

**Question:** What is the recoverable result/error representation, how are payload owners transferred, and how do C errors and task failures map into it? What must callers explicitly handle?  
**Direction:** Deterministic behavior and no mandatory heavyweight unwinder. `Result`, tagged alternatives, `throws` and other spellings remain unselected.  
**Resolve before:** ERROR-1 and the async completion contract. [R1, §34]

### Q06 — Callable captures and foreign retention

**Question:** How do function values distinguish no environment, bounded borrowed capture and owned escaping environments? How are copy, move and destruction represented? What may a C callback retain?  
**Direction:** Function/environment/lifetime form one logical value; no discarded capture or destruction channel. Choose the minimum useful first scope.  
**Resolve before:** CALLABLE-1; later CABI-EXT-1/GObject callback support. [R1, §24]

## 6.2 Object, aggregate and generic ownership

### Q07 — Allocated unique object construction

**Question:** How does source select independently allocated storage while preserving cheap lexical construction? What are failure, move/rebind, identity and promotion rules?  
**Direction:** Unique deterministic ownership; construction is not permanently one global heap. Existing lexical/caller-provided behavior is not silently reinterpreted.  
**Resolve before:** OBJ-ALLOC-1; coordinate with Q25.

### Q08 — Owned child objects and field extraction

**Question:** How are child fields initialized, replaced and destroyed? Can ownership be extracted, and what restores a valid field? Which self-/cross-links are allowed?  
**Direction:** Preserve exact cleanup and valid storage. Buffer `swap` is not general field-move authorization. Non-owning links require independent lifetime rules.  
**Resolve before:** OBJ-FIELD-2; any general extraction extension.

### Q09 — Declaration-level lifetime policy

**Question:** How is an abstraction’s unique/shared default declared, and are exceptional use-site policies permitted? How does this interact with construction, generics and adapters?  
**Direction:** Declaration-level common policy is preferred; `shared class` remains a possible spelling, not frozen grammar. Ownership must remain separate from dispatch and nullability.  
**Resolve before:** SHARED-1 and broader object-policy changes. [R1, §66]

### Q10 — Derived move-only structs and partial state

**Question:** How do owning fields determine whole-value move/cleanup, partial initialization, partial moves and failure paths? How is a move distinguished from an identity-object transfer?  
**Direction:** Derive copyability/movability/cleanup from fields when possible, with useful field-path diagnostics; no redundant `SimpleType` or move-only marker for the ordinary case.  
**Resolve before:** STRUCT-MOVE-1. [R1, §67]

### Q11 — Generic borrowing and owner-local composition

**Question:** How can generic code borrow a direct ownership-bearing value without consuming it, and store a local owner safely? How do default borrowing, capabilities and ordinary copied `T` coexist?  
**Direction:** Extend shared semantic authorities, not a second generic ownership system. Do not retroactively reinterpret current plain value transport.  
**Resolve before:** GEN-BORROW-1 / GEN-OWN-2 / GEN-MEMBER-1.

### Q12 — Nullability, refinement and compatibility

**Question:** Should references become non-null by default, with what nullable spelling and migration rules? Which checks refine locals/fields across calls or suspension? What checked narrowing or explicit unsafe escape is allowed?  
**Direction:** Strong safe-default candidate; current Class/Resource contracts are nullable. Non-null does not prove lifetime, and moved is not merely null.  
**Resolve before:** NULLABILITY-1; coordinate with async and weak acquisition. [R2, S05]

### Q13 — Recoverable allocation

**Question:** How can allocation failure return a usable error rather than terminate? How does that result compose with arrays, objects, libraries and custom allocators?  
**Direction:** Existing `new ... else void_call(...)` is intentionally fatal and allocation-site-local. Do not silently change it into retry, fallback storage or recovery.  
**Resolve before:** Any recoverable-allocation extension under ERROR-1 / ALLOCATOR-1. [R8]

## 6.3 Shared lifetime, dispatch and properties

### Q14 — Shared lifetime and weak acquisition

**Question:** Which shared operations are allowed, which counts are atomic, and what is the cycle policy? How does a weak reference obtain a live owner without racing destruction?  
**Direction:** Optional explicit cost; weak is expiration-aware, borrow is lifetime-bounded. A minimal shared implementation must not claim full thread safety.  
**Resolve before:** SHARED-1 / WEAK-1.

### Q15 — Inheritance, interfaces and runtime type information

**Question:** What inheritance/interface model is required, what is the override/cast contract, and which types require runtime descriptors or reflection?  
**Direction:** Native dispatch and metadata are pay-for-use. Unique lifetime does not prohibit interfaces; every class need not behave like GObject.  
**Resolve before:** DISPATCH-1 / INTERFACE-1; reflection remains separately scoped. [R1, §§11, 33]

### Q16 — Lazy property state and failure

**Question:** What happens on recursive initialization, failed evaluation, destruction during use or concurrent first access? Is invalidation/reset supported, and how does a cached owner behave?  
**Direction:** First successful evaluation and later cached reads are the founding model. Final syntax, failure caching, reset and synchronization are not decided.  
**Resolve before:** LAZY-1; later owning/async lazy extensions. [R1, §19]

### Q17 — Property value and ownership contracts

**Question:** Does each property return a copy, a borrow or a transferred owner, and how is that intent expressed? Can setters consume or replace state? Which stored/automatic forms are useful?  
**Direction:** Resource-valued properties are deferred, not permanently rejected. Preserve accessor effects; computed access is not implicitly lazy.  
**Resolve before:** PROP-LIFE-1 / PROP-COMPOSE-1; coordinate with TEXT-OWN-1.

### Q18 — GObject/GIR identity and lifetime translation

**Question:** How are repeated conversions mapped to stable wrappers, and how are cross-boundary strong/weak references, callbacks, signals, cycles and threading handled? Which GIR import/export subset comes first?  
**Direction:** Foreign adapters, not native GObject semantics. Do not choose an identity table or header strategy without the lifetime contract.  
**Resolve before:** GOBJECT-1 / GIR-1. [R1, §§14–16]

## 6.4 Text, bytes and containers

### Q19 — Owned text and borrowed substrings

**Question:** What owns generated UTF-8, what representation does a borrowed view retain, and how can results, fields and collections store each safely? Which substring operations preserve valid encoding?  
**Direction:** Preserve current text identity/invariants unless an explicit decision changes them. Byte length, scalar count and display graphemes are different quantities.  
**Resolve before:** TEXT-OWN-1 / TEXT-LIB-1.

### Q20 — Collection growth and view invalidation

**Question:** What are length/capacity, growth, reserve and failure rules? When can elements relocate, how are move-only elements handled, and what invalidates an outstanding view?  
**Direction:** An owning array is not already a resizable container. No unsafe reallocation hidden beneath an apparently stable borrow.  
**Resolve before:** CONTAINER-1; coordinate with STRUCT-MOVE-1 and allocators.

### Q21 — External bytes, paths and formatting

**Question:** How do raw file/path bytes enter the language, where is UTF-8 validated, and what APIs parse/format numeric or structured text? Are formats checked at compile time?  
**Direction:** Text entry does not promise arbitrary OS-byte preservation. Keep binary input distinct; expose allocation and error policy. No silent locale conversion or mandatory formatting engine.  
**Resolve before:** BYTES-IO-1 / TEXT-LIB-1 / FORMAT-1.

## 6.5 Systems types, targets and optimization

### Q22 — Wider integers, sizes and arithmetic modes

**Question:** Which fixed/pointer-sized names and conversions are needed? How do array lengths and foreign sizes migrate? Which checked and saturating operations remain to be added beyond current primitives?  
**Direction:** Existing `int`, exact conversions and wrapping semantics remain stable until explicitly superseded. Copying a target width into semantic identity is not a portability design.  
**Resolve before:** INT64-1 / SIZE-1 and relevant numerical extensions.

### Q23 — Public optimized builds

**Question:** What optimization levels/pipelines become supported, with which target defaults, reproducibility and cost reporting? How are exact rounding, allocation failure, traps and observable calls preserved?  
**Direction:** Public optimization is missing despite internal optimized qualification. Profile compiler latency separately; do not invent unsafe global fast math to obtain a speedup.  
**Resolve before:** OPT-PIPELINE-1. [R2, S03]

### Q24 — Broader C contracts and stable boundaries

**Question:** Which real APIs first require widths, typed buffers/pointers, structs/unions, out/in-out arguments, callbacks, constants/header expressions and retention? How are layout and native/foreign identity distinguished?  
**Direction:** Strongly typed explicit boundaries; C is permanent. No bitcast-based acceptance or assumption that matching pointer/width carriers prove the full contract.  
**Resolve before:** CABI-EXT-1 and affected adapter campaigns. [R1, §13]

### Q25 — Allocator authority and lifetimes

**Question:** How is heap/arena/region/pool/static storage selected, and who retains the allocator or region? What allocation failure, alignment, destruction and escape rules apply?  
**Direction:** No mandatory global heap, hidden lifetime extension or undeclared runtime dependency. Construction and allocation policy must stay separable.  
**Resolve before:** ALLOCATOR-1; coordinate with objects, frames and containers. [R1, §§31–32]

### Q26 — First embedded deployment and hardware access

**Question:** What exact target/board or execution environment comes first, and what backend, startup, linker, ABI and runtime work is required? Which MMIO, volatile, interrupt and atomic rules are necessary?  
**Direction:** Dreamcast/SH-4 remains a real architectural workload; easier host evidence cannot replace it. General multithreading is not established by cooperative async.  
**Resolve before:** DRIVER-TARGET-1 / EMBEDDED-1; before any claimed concurrency support.

### Q27 — SIMD breadth and floating policies

**Question:** Which f64/wider vectors, alignment/load/store/reduction facilities are most useful? How are explicit fused or relaxed policies scoped and composed with strict defaults?  
**Direction:** Preserve current numerical guarantees and qualified primitives. Distinguish semantic operations from target-specific intrinsics and measured hardware support.  
**Resolve before:** SIMD-POLICY-1 and target expansion. [R1, §§26–30]

## 6.6 Projects, ergonomics and maturity

### Q28 — Modules versus separate compilation

**Question:** What names, imports, visibility and dependency rules are needed? Later, how are generic bodies, native ABI versions and compiled interfaces distributed?  
**Direction:** One global multi-source program is the current model. Do not conflate namespaces, C object linkage, packages and independently compiled Astra modules.  
**Resolve before:** MODULE-1; a separately authorized compiled-unit campaign.

### Q29 — Tooling and diagnostic provenance

**Question:** Which formatter/editor/debugger capabilities are required first? How are optimized source locations and embedded caller snippets handled, including path/privacy controls?  
**Direction:** Inspect current external tooling before duplicating it. Source-aware diagnostics are useful but neither a debugger nor a privacy scrubber.  
**Resolve before:** TOOLS-1 and relevant public optimization/debug features.

### Q30 — Named alternatives and control-flow convenience

**Question:** What enum/alternative representation and selection/exhaustiveness rules are appropriate? Which counted-loop/iteration constructs should arrive first, and how do they preserve cleanup and borrow scopes?  
**Direction:** Remove routine boilerplate without importing a large interacting type system. Coordinate alternatives with ERROR-1 rather than preselecting its representation.  
**Resolve before:** ENUM-1 / CONTROL-1.

### Q31 — Comparison-chain semantics

**Question:** Which comparison operators may chain, how are shared operands captured once, and when are later operands skipped? What happens for mixed types, NaNs or vector results?  
**Direction:** A strong readability candidate; current comparisons are ordinary left-associative binary expressions. No implicit numeric promotion or mask-to-bool reduction follows from chaining.  
**Resolve before:** COMPARE-CHAIN-1. [R2, S11]

### Q32 — `with` name resolution and receiver identity

**Question:** Do members require a leading dot, how are lexical conflicts diagnosed, and does the receiver refer to original storage or a temporary value? What prevents invalidating its owner during the block?  
**Direction:** Evaluate the receiver once and keep storage/lifetime meaning clear. The previously suggested leading-dot form is not approved syntax.  
**Resolve before:** WITH-1. [R9]

### Q33 — Regex dialect and runtime cost

**Question:** Which literal grammar, flags and regex dialect are supported? Are constant patterns validated or compiled ahead of time, and what are construction, reuse, allocation and JIT costs?  
**Direction:** Optional text capability; unused programs acquire no regex runtime. Literal convenience must not silently select an engine or mandatory JIT.  
**Resolve before:** REGEX-1. [R9]

### Q34 — Remaining inference and immutable bindings

**Question:** Which unresolved-generic locals can safely infer their exact type, and is a separate runtime immutable-binding facility needed? What aggregate constants or compile-time execution, if any, are justified?  
**Direction:** `var` and concise `const` are canonical; current `const` is compile-time. Do not introduce `let`, `readonly`, CTFE or aggregate constants by implication.  
**Resolve before:** Any dedicated inference/immutability/compile-time extension.

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

Reconcile the audited stale object/generic claims, syntax heading and milestone label against later qualification. Keep historical reports unchanged and make the amendments, capability matrix and roadmap easy to find together. These standalone documents do not edit the repository. [R2, S12]

# 8. Revision policy and working record

## 8.1 The next decision

Complete COMPILE-PROFILE-1 within its observational scope. Carry out the small documentation reconciliation, then prepare ASYNC-CONTRACT-1 as the next major language-design checkpoint, with the first callable/executor needs identified explicitly. Bring LAZY-1 into the same near-term planning window. Keep owned data/text and the public target/toolchain tracks active rather than allowing CAD optimization to absorb the roadmap.

This preserves the preceding roadmap’s direction. It does not preapprove an error syntax, task runtime, nullable-type spelling, shared-class grammar or a regex engine. Those decisions remain in section 6 until deliberately closed.

## 8.2 Revision log

**Version 1.0 — 2026-09-27.** Consolidates the vision, amendments, source findings, milestone tracks, 35 open questions and adherence rules. Accepted baseline: OWN-SWAP-1. COMPILE-PROFILE-1 remains Submitted. No implementation or repository change.

Future revisions should state which accepted milestone or explicit design decision caused the change. Retain stable question IDs and a short supersession note. Revise priorities when evidence warrants it, but explain the change rather than quietly replacing the path.

---

**Working commitment:** build the language we actually want, keep current facts separate from future promises, and make every justified detour lead back to that path.

# 9. Sources and provenance

The bracketed references are portable document references, not claims that local build paths remain available. The source audit contains the exact path/line excerpts and file hashes for implementation findings. The future tracks and open-question alternatives are planning synthesis from these materials and the project discussion; they are not external research or executed results.

<a id="ref-r1"></a>
**[R1] Founding Bible, with amendments.** `ASTRA_FOUNDING_BIBLE_2026-09-13.md`, 2,170 lines. Sections 0–63 establish the architecture; sections 64–68 record human/AI reviewability, inference, ownership and struct-value amendments. Snapshot SHA-256: `32ab9a23679b98cd2dc56bb93f2a47386be63cc3e2fbb0deb6cae1f019922246`.

<a id="ref-r2"></a>
**[R2] Source audit and uploaded code.** `ASTRA_ROADMAP_SOURCE_AUDIT.md`, sections S01–S12, SHA-256 `f1e9a36d66486d70d4d3d2b0b1d74520ed27b26e9b245f61885737c0fd0a5e46`. Audited archive: `astra.tar.xz`, SHA-256 `94fbb06549f3953c84796163e947e6d846e6cbf8d7018e974e36c1237c2b64c3`. This is static inspection, not a compiler rebuild. Archive/package identity limits are stated in section 3.1.

<a id="ref-r3"></a>
**[R3] OWN-SWAP-1 qualification.** `docs/own-swap-1-validation.md`; accepted source/runtime/ownership/application scope, benchmark limitations, memory categories and cleanup history. Supplied report SHA-256: `1cb8d0866a5e764958e72324b474e6253563837748ac4d45b76224a388bf2d82`.

<a id="ref-r4"></a>
**[R4] OWN-SWAP-1 final delivery.** `build/own-swap-1/inventory/final-state.json`, recorded 2026-09-27. Commit `ca7c2301c60f92185e1c8689b3d41f470ee92b0f`, tree `09f6ba544ea3a30a764cf30d644dd08b5a23ddcb`, one commit and clean worktree. The reported Git delivery archive is distinct from the uploaded inspection package.

<a id="ref-r5"></a>
**[R5] Complete CAD application checkpoint.** `docs/app-cad-2-validation.md` and its workload/source map. Full native-state I0 qualification and original L/P/I distinctions. Supplied report SHA-256: `84804e518ae59e16725cdbd814f7f096e2412267d9b63189a6ee4c6a68cda308`. OWN-SWAP supplies the later I1 extension; older blocked checkpoints remain historical.

<a id="ref-r6"></a>
**[R6] Generic values and collections.** `docs/gen-copy-1-validation.md`, `docs/gen-slice-1-validation.md`, `docs/gen-buffer-1-validation.md`, and corresponding current language/IR guides inspected in R2. Read each milestone in sequence: later accepted capabilities supersede earlier bounded exclusions without changing the older report’s historical result.

<a id="ref-r7"></a>
**[R7] Submitted observational campaign.** `ASTRA-COMPILE-PROFILE-1-SUBMISSION.md`, SHA-256 `270f55e376b10229d7d93185aa49814d5329ddd200d6f36a5b49672fb32fb286`. This is a submission, not a completed profiling report or optimization decision.

<a id="ref-r8"></a>
**[R8] Existing failure and text boundaries.** `docs/alloc-fail-1-validation.md`, `docs/text-1-validation.md`, `docs/text-io-1-validation.md`, `docs/args-1-validation.md`, `docs/diag-1-validation.md`, and the current guides excerpted in R2. These distinguish fatal actions, borrowed/static text, argument capture and assertions from future recovery/owned-text features.

<a id="ref-r9"></a>
**[R9] Project discussion and adoption.** The conversation’s human/AI vision, inference and implicit-borrow amendments; unique/shared/weak and value-semantics discussion; rejected Jai declaration direction; Vala-inspired comparison/nullability/with/regex candidates; the preceding source-based roadmap; and the request to make this a maintained Markdown/PDF planning reference. Candidate syntax is preserved as unresolved, not silently ratified.

