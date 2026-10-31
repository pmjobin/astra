---
title: "ASTRA - Vision, Roadmap & Open Decisions"
subtitle: "Version 2.0 | Attribute-policy and COM interoperability revision"
author: "Asteria & Pierre-Marc"
date: "18 October 2026"
lang: en
---

# ASTRA

## Vision, Roadmap & Open Decisions

**Version 2.0 - 18 October 2026**  
**Status:** Living planning reference; new attribute semantics are design direction, **not compiler implementation**.  
**Current accepted source baseline reported:** `959c47cb31cc7847150752ab26615545953a3400` (Systems & DSP Surge 9; scoped PASS).  
**Current submitted campaign:** `ASTRA-LANGUAGE-GENERALIZATION-SURGE-10`, pinned to that baseline; **no Surge 10 completion is established by this document**.  
**Canonical design companion:** `ASTRA_FOUNDING_BIBLE_2026-10-18.md`, sections 69-82.  
**Historical predecessor:** `ASTRA_VISION_AND_ROADMAP_v1.0_2026-09-27.md` (preserved, not overwritten).

> **Make sophisticated systems programming look ordinary.**  
> Native first. Compatibility at explicit boundaries. Declare policy once; derive its consequences; make costs and risks discoverable.

This roadmap updates implementation status after the accepted 2026 engineering campaigns and integrates the October 18 semantic-attributes and COM discussion into the previously agreed **five-surge program (Surges 10-14)**. It is a planning document, not authorization to edit a running submission or a claim that any proposed syntax is implemented. Its Markdown edition is the editable master; the PDF is a matching reading copy.

## At a glance

| Dimension | Decision / position |
| --- | --- |
| Architectural doctrine | Compiler-owned native semantics; optional foreign ABI adapters; deterministic ownership; low review burden |
| Current demonstrated scope | Hosted GNU x86-64 native programs, O0/O1/O2, C/GObject/GIR subsets, single-threaded async file I/O, modules/debugging; Linux no-libc and finite DSP/arena/volatile work |
| Current submission | Surge 10, **unchanged and already issued** |
| Future program | Surge 11 numerical/optimizer; Surge 12 no-OS/allocators; Surge 13 concurrency; Surge 14 attributes/interoperability/tooling/release |
| Newly agreed design | `[Shared] class` means **intrinsically intrusive shared Class instances by default**; `shared T` means **non-intrusive boxed sharing** of an otherwise eligible nonshared type |
| Added interoperability goals | `[CImport]`, `[CExport]`, `[COMImport]`, `[COMExport]`, `[GObjectImport]`, `[GObjectExport]`, with independent ABI/lifetime proofs |
| Express deferrals | **SH-4/Dreamcast qualification** and **self-hosting** are out of Surges 10-14. Real non-SH-4 no-OS execution remains required. |
| Release goal | Independently installable, reproducible Astra full-feature **developer release candidate**, with an auditable Bible conformance matrix; not an unconditional 1.0 promise |

---

# 1. Authority, continuity and vocabulary

## 1.1 Which document governs what?

1. The **current committed compiler, its actual Git HEAD and accepted source-bound test evidence** govern what Astra demonstrably does.
2. The **October 18 Founding Bible** governs architectural direction, including the new sections 69-82 on attributes and foreign object models.
3. This **Roadmap v2.0** governs sequencing, dependency and acceptance intentions, subject to later explicitly approved revisions.
4. The **September 27 Roadmap v1.0** preserves earlier priorities, historical receipts and the original Q01-Q35 question text. Its stale implementation status is **superseded**, not retroactively rewritten.
5. Actual Codex engineering authority comes from the **individual, Git-pinned native `$pm-next` submission and any necessary user approval**, not from a roadmap example or an attribute name mentioned here.

This document was prepared from the supplied Surge 9 report evidence, the existing Surge 10 engineering packet, Roadmap v1.0 and the October 18 Bible. **No fresh compiler, kernel, Windows, GObject, target-board or full-regression execution was performed for this editorial revision.**

## 1.2 Status vocabulary

| Label | Exact meaning |
| --- | --- |
| **ACCEPTED (bounded)** | A real accepted campaign delivered a capability within the written platform/type/effect/test profile. Not universal support. |
| **IN FLIGHT** | A Git-pinned engineering packet is submitted, but its accepted completion is not established here. |
| **AGREED DIRECTION** | Explicit joint design choice. Precise grammar, ABI and code remain to be approved and built. |
| **RECOMMENDED / CANDIDATE** | Worth testing or deciding, but not frozen semantics and not an automatic implementation mandate. |
| **OPEN** | An unresolved language/ABI/lifetime contract with an identified decision gate. |
| **HELD / INCOMPLETE** | A qualification or product gate that cannot be claimed complete. Historical records are immutable. |
| **DEFERRED** | Intentionally excluded from this surge sequence; not rejected forever. |

In particular, passing a new owning-lazy suite does **not** retroactively complete historical LAZY-1 Q4, and producing an AArch64 object does **not** prove no-OS execution.

## 1.3 Nonnegotiable design character

Astra retains a C#/Vala-like readable source surface; local type inference; unique, deterministic native Classes by default; copying/movement derived from aggregate fields where possible; compiler-visible native properties and lazy state; meaningful syntax for danger or high cost; first-class C interoperability; freestanding viability; fixed-vector/DSP semantics; and optional runtime services. No mandatory GObject, COM, garbage collector, refcount or heavyweight unwinder for ordinary programs.

Reviewability is an acceptance dimension. Every major new capability must include at least one natural, human-readable program, an explanation of lifetime/cost implications and evidence of correctness. Novel syntax is not justified solely by parser feasibility.

---

# 2. Current accepted capabilities and remaining breadth

## 2.1 Baseline snapshot (after Surge 9, before Surge 10 qualification)

The latest accepted report in this handoff is `ASTRA-SYSTEMS-DSP-SURGE-9`, **PASS**, from `482d477a389d599a58aa36ff72e542b202033d46` to `959c47cb31cc7847150752ab26615545953a3400`, tree `31682db52a53397f9c99688a03ccc7fcc9e2de93`. The report records 40/40 selected regressions, 238 focused command checks, eight A65-A72 applications, and a strict source-dependent build. These are report-backed hosted observations, not a rerun here.

| Program family | Already accepted, within finite profiles | Unfinished / next action |
| --- | --- | --- |
| Parser / semantic / LLVM | Checked semantic IR, CFG/SSA, native LLVM lowering; public O0/O1/O2, object emission, initial target/layout options, native modules | Broader optimization semantics, expanded target/runtime ABI and full integration qualification |
| Ownership / Classes | Unique Classes, owning children, shared/weak boxed handles (single-threaded), finite move-only records, exception rollback and native interfaces | General nested/generic record and enum ownership, general allocation policy, intrusive `[Shared]` model not yet implemented |
| Generics / collections | Generic borrows/consumers/results/locals in qualified domains; exact-Class `Bag<T>`, growth, extraction/replacement | General generic element/member/iterator and aggregate composition |
| Text / I/O | Owned validated UTF-8, counted builder, text parsing/formatting, bulk POSIX file I/O | Fuller Unicode/value APIs, portability and package-quality standard library |
| Callables / async | Typed functions/closures, retained C callbacks, real single-threaded liburing 2.15 timer and file payload execution | General concurrency, sockets/network stack, thread-safe shared/weak, cross-thread async, broad foreign callback ABI |
| Native object features | Properties, first-success/owned lazy cache slices, virtual/interface dispatch, bounded nullable refinement | General typed property/aggregate composition, full lazy/virtual/async cases, policy attributes/monitor/singleton/reactivity |
| Interop | C typed buffers/POD/callbacks; selected GObject import/signals/GIR; separate Astra native modules | Full GObject **export**, broader C/GIR marshalling, **COM import/export** (not implemented), foreign lifetime composition |
| Systems / DSP | `f64<2>`, `i64<2>`, `u64<2>`, saturation; Linux x86-64 no-libc/CRT profile; finite typed arena; verified mapped volatile ops; AArch64 object-only | Full SIMD/DSP/FP policy, real optimizer proofs, generalized allocators, **actual non-SH-4 bare-metal execution** |
| Tooling | Formatter, source diagnostics, `-g`/DWARF4 selected GDB variables, versioned native module linking | Language server, packaging, richer debugging, semantic-policy explanations, standalone installer/release |

Cumulative application witnesses: **A01-A72**, delivered across previous campaigns. This does not mean all 72 have been freshly rerun together. Surge 10 targets A73-A84; Surge 14 must freshly qualify the full selected corpus and historical registry as a distinct acceptance gate.

## 2.2 Important unresolved historical evidence

- **LAZY-1 Q4:** `HELD/INCOMPLETE`. Accepted later lazy-property implementations do not alter that historical status without a separately authorized, evidence-backed closure.
- **Surge 3** and original **Surge 6:** historical PARTIAL outcomes. Successor campaigns delivered their missing finite obligations; never overwrite original reports.
- **Surge 7** had a reported omission of `src/syntax/token.vala` from one source export; subsequent live Git and source-bound evidence, not invented reconstruction, governs its identity.
- **Surge 9:** Linux no-libc is still a Linux process; AArch64 emitted object was **OBJECT_ONLY**; real bare-metal/SH-4 were not executed.
- Full historical 9,000+ registration suite, full application corpus, comprehensive AEP workload and a portable release were not freshly qualified as one complete program by Surge 9.

---

# 3. Attribute and semantic-policy architecture (Bible §§69–82)

## 3.1 The new organizing principle

**AGREED DIRECTION:** Astra should use familiar Vala-like `[...]` declaration attributes as a principal means of stating *optional compiler-recognized semantic policies*. Those policies affect real meaning—ownership, allocation, synchronization, ABI, effects, caching or metadata—not just decoration or unverified source rewriting.

```astra
[Shared, Monitor, Singleton]
class Registry { }

[CExport, COMExport, GObjectExport]
class Service { }
```

*All examples in this chapter are sketches, not evidence of accepted syntax or permitted policy combinations in today's compiler.*

The implementation substrate should include typed arguments, resolved policy identities, declaration-site legality, cross-policy conflict analysis, inheritance/specialization/module rules, semantic effect/ownership facts, native/foreign ABI adapters, code-size/runtime dependency accounting, negative IR-verifier tests and compiler-visible policy inspection. The order of compatible policies should not change their meaning.

**No arbitrary user-defined semantic rewrites are approved.** First deliver built-in recognized contracts and ordinary nonsemantic metadata; evaluate programmable annotations/macros separately if a real workload justifies them.

## 3.2 `[Shared]` and `shared T` are intentionally different

**AGREED DIRECTION - selected by the user:**

```astra
class Image { }                 // Unique Class by default.

[Shared]
class Texture { }               // Every ordinary Texture owner is intrinsically shared.

shared Image boxed_image = ...; // Non-intrusive shared box around a nonshared T.
```

| Form | Meaning | Physical expectation | Main proof obligation |
| --- | --- | --- | --- |
| Ordinary `class Foo` | Unique owned identity and deterministic lifetime by default | No compulsory reference header | Correct move/borrow/release |
| `[Shared] class Foo` | **Every Foo owning instance handle is intrinsically shared by default**; no redundant use-site `shared Foo` | Intrusive strong ownership state associated with object allocation | Copy/retain/clone policy, weak expiration, identity and final destruction |
| `shared T` for otherwise eligible `T` | Optional non-intrusive shared ownership wrapper | Separately managed box/control block | Box/owner movement, release, weak/allocator compatibility |
| Existing `Shared<T>`/`Weak<T>` | Already tested finite library/runtime facilities | Do not assume new spelling or migration | Preserve source, ABI and old regression behavior |

**OPEN:** implicit retain-on-copy versus explicit `clone()`; meaning of `shared` applied to a `[Shared]` type; weak-control anchor placement; threading memory order; inheritance; allocation/failure; and migration of `Shared<T>`. Until a design decision, new language sugar must not silently change existing assignment, copying or ABI rules. Refcount safety is *not* synchronization of mutable fields.

## 3.3 Synchronization, instances and actors

| Policy | Status | Intended meaning | Critical constraints |
| --- | --- | --- | --- |
| `[Monitor]` (original suggestion `[Mutex]`) | RECOMMENDED, spelling OPEN | Automatic, statically bounded synchronization of protected instance operations | Reentrancy; nested locks/deadlock risk; methods/properties/callbacks; no unqualified `await` while locked; escape of mutable borrows |
| `[Singleton]` | RECOMMENDED, scopes OPEN | Process-, thread- or executor-scoped instance authority | Init/failure/recursion/destruction; freestanding availability; owner anchor/shutdown |
| `[Actor]` | CANDIDATE | Serialized executor/message-driven object | Mailbox, task ownership, cancellation and error handling; not the same as monitor locking |
| `[ThreadBound]` | CANDIDATE | Restrict a value to one thread/executor | Borrow/callback/foreign transport proofs |
| COM apartment/agility policy | OPEN, platform-specific | Enforce COM apartment and marshalling contracts | A synchronized object is not automatically COM agile |

The combination `[Shared, Monitor, Singleton]` is a *goal for safe composition*, not an automatically approved transformation. The singleton's strong anchor, weak upgrades during shutdown, and lock/lifetime semantics must be checked together.

## 3.4 Distinct foreign personalities of one native type

Use explicit ABI attributes; do not overload native module `[Import]`/`[Export]` with ambiguous foreign meaning.

| Adapter policy | Planned ABI contract |
| --- | --- |
| `[CImport]` / `[CExport]` | Exact C symbols/layout when appropriate; typed pointers/arrays/unions/callbacks/errors; C export normally opaque Class handles with construction/destruction and retain/release generated according to native ownership policy |
| `[COMImport]` / `[COMExport]` | COM/DirectX-style `IUnknown`, IID/GUID, vtables/calling conventions, `QueryInterface`, `AddRef`, `Release`, canonical identity, `HRESULT` and out arguments; checked lifetime and foreign consumer execution |
| `[GObjectImport]` / `[GObjectExport]` | GType-aware adapters, g_object_ref/unref, properties, signals, GIR/typelib, callback/finalization/weak lifetime; optional GLib dependencies |
| `[Repr(C)]` | Target-verified C-compatible **value** layout; not an excuse to expose raw native identity-Class layout |

**COM import/export is newly added future scope, not part of an already approved Surge 10 packet.** A first COM success requires **real independently compiled foreign interface execution** on a qualified ABI/host (normally Windows for native COM). A Linux header/layout test or unexecuted cross object is not enough. A working in-process IUnknown interface does not automatically establish activation, registration, apartments, cross-process marshaling, connection points, type-library tooling, aggregation or WinRT.

An imported interface and exported native object must preserve interface identity and pointer/reference lifetime across `QueryInterface`. A `[Shared]` native object may back a COM or GObject adapter, but intrusive Astra lifetime does **not** imply the native allocation has either foreign layout. A single native object may have distinct C, COM and GObject wrappers; their dual ownership/identity and cycle rules must be explicitly proven.

### Example (proposed)

```astra
[Shared, COMExport]
class ImageProcessor : IImageProcessor { }

[COMImport(iid = IID_ID3D12Device)]
interface ID3D12Device : IUnknown { }

[Shared, GObjectExport]
class ApplicationSettings { }
```

`[CExport]` does not imply COM activation; `[COMExport]` does not imply Windows registration; `[GObjectExport]` does not make every Astra Class a GObject. Foreign code cannot unwind native checked exceptions across ABI boundaries.

## 3.5 Laziness is not dependency tracking

- `[Lazy]` - first-success-on-demand cache with checked failure/recursion/owner-lifetime semantics; determine if it is sugar over the existing native lazy property construct.
- `[Tracked]` - **CANDIDATE** dependency graph with explicit invalidation, cycles, observable updates and cache ownership rules.
- `[Observable]` - **CANDIDATE** change subscriptions with callback/lifetime and effect contracts.
- `[Memoized]` - **CANDIDATE** function-result caching, with key/equality/eviction/allocator/effect contracts.

Do not make plain lazy caches reactively invalidating by implication, or silently turn ordinary computed getters into cached properties. Reactive graph semantics need their own approved design and tests. They are not already-implemented requirements just because a `[Lazy]` spelling is proposed.

## 3.6 Additional policy candidates and placement

| Policy | Status entering future surges | Primary campaign / proof |
| --- | --- | --- |
| `[Reflect]` | Agreed opt-in metadata direction; exact public API OPEN | Surge 10 metadata baseline; Surge 14 introspection breadth, pay-only-for-used metadata |
| `[Derive(Eq, Hash, Debug)]` | CANDIDATE | Surge 10/14; derivation only for checked eligible field graphs, no hidden expensive behavior |
| `[NoEscape]` | CANDIDATE contract | Surge 13/14; foreign-retained callback/borrow proof, explicit trusted boundary |
| `[Pure]` / `[MustUse]` | CANDIDATE | Surge 11 and 14; effect proofs and meaningful diagnostics; no blind optimizer trust |
| `[Align]` / `[Repr(C)]` | CANDIDATE spellings | Surge 11/12 and 14 ABI; target-verified layout and allocation |
| `[Allocator(...)]` | RECOMMENDED | Surge 12; lifetime, alignment and failure proofs |
| `[Interrupt]` | CANDIDATE | Surge 12; only on independently qualified selected target |
| `[Deprecated]` | CANDIDATE | Surge 14 tooling/API version diagnostics |
| `[Agile]` / `COMExport(threading=...)` | OPEN | Surge 13/14, with actual apartment evidence |
| `astrac --explain-semantics ...` | CANDIDATE developer tool | Surge 14, inspect derived ownership, lock/metadata and foreign-adapter costs |

Attribute names and arguments are **not frozen merely because this table names them**. The implementation roadmap must include explicit accept/reject decisions and regression tests rather than inventing hidden behavior to make examples parse.

---

# 4. Five coordinated engineering surges: 10-14

## 4.1 Execution approach

The aim is a **fully featured, broadly useful Astra compiler and runtime**, with self-hosting deferred. A surge is a substantial, multi-session engineering *objective*, not an arbitrary number of hours or a license to mark difficult work PARTIAL. Each surge has required executable gates, integration tests and a resumable handoff.

**Scope is ambitious, but not a guaranteed schedule.** Independent approvals remain required for incompatible changes or new platform/ABI commitments. Real permission, resource, security and session limits are binding. No amount of planned work replaces a qualified execution environment.

| Surge | Integrated focus | Primary end-to-end evidence |
| --- | --- | --- |
| **10** | Complete practical language composition | A73-A84, nested owning values, generics, iterators, properties, metadata, cross-module ABI |
| **11** | Numerical + optimizer semantics | Real AEP-like DSP, strict/relaxed FP comparisons, generated-code and performance evidence |
| **12** | Freestanding + general allocation | Actual **non-SH-4 no-OS** program, independent memory/layout/allocator proofs |
| **13** | Threading + runtime + network | Real concurrent ownership, monitors, threads, cancellation, TCP/UDP and memory-model tests |
| **14** | Attribute/interoperability + developer release | GObject/C/**COM** foreign clients, package/LSP/debug tools, reproducible install, comprehensive regression/Bible audit |

## 4.2 Surge 10 - Language Generalization (ALREADY SUBMITTED; KEEP UNCHANGED)

**Existing submitted task:** `ASTRA-LANGUAGE-GENERALIZATION-SURGE-10`, base `959c47cb31cc7847150752ab26615545953a3400`. This roadmap update **does not amend its manifest, acceptance matrix, source scope, or permissions**. Do not rebase or mutate the in-flight task to add `[Shared]`, COM, monitor or reactive-graph work.

**Nine required streams already in its work order:**

1. **G1:** Recursive/nested owning records and tagged alternatives with aggregate-level move/cleanup, field extraction and checked-prefix rollback.
2. **G2:** Broader generic classes/members/containers across copyable records, unique Classes and move-only resource aggregates.
3. **G3:** Reusable iterators, bounded stateful iteration and borrow-safe mutation/invalidation.
4. **G4:** Owning, generic, virtual and lazy properties; selected checked/async composition without retroactively clearing LAZY Q4.
5. **G5:** Generalized opt-in non-null and loan proofs; preserve today's nullable default.
6. **G6:** Text/value ergonomics and opt-in native type descriptors; only justified optional regex support.
7. **G7:** Ownership-safe independently linked generic/aggregate modules and versioned ABI checks.
8. **G8:** Twelve genuinely distinct applications, **A73-A84**.
9. **G9:** Native O0/O1/O2, compiler-verifier, memory, old-regression and current-documentation integration.

**Attribute-system interface to downstream work:** Inspect whether the submitted work creates useful annotation/metadata infrastructure. Preserve and reuse it where proven; any new semantic attribute beyond its approved scope waits for a newly pinned surge submission/ADR. Generic/metadata design must avoid precluding later declaration-level intrusive `[Shared]`.

**PASS only** for all contracted G1-G9 in the actual submitted task. This roadmap is not permission to weaken or redefine those gates.

## 4.3 Surge 11 - Numerical, DSP and semantic optimization

### Required implementation outcomes

- Generalize fixed vectors, masks, aligned/unaligned load/store, selection, shuffle, reductions, conversions and saturating integer operations with portable semantics and target-dependent lowering.
- Supply usable DSP/vector and numerical library abstractions grounded in a real AEP-style workload; complex/matrix primitives should be engineered where they measurably help.
- Add **explicit composable floating-point policy** covering default strict behavior and approved dimensions such as FMA contraction, finite-only, reassociation, approximate reciprocal, NaN and signed-zero assumptions. Specify effect and scope independently of the host compiler's global fast-math flags.
- Derive justified alias/noescape facts, escape/stack promotion, object/aggregate scalar replacement, property and lazy-cache elimination, devirtualization, specialization, redundant retain/release elimination and relevant IR-to-LLVM facts.
- Investigate checked `[Pure]`, `[Align]`, `[MustUse]` policy semantics or a minimally sufficient attribute substrate. Only approved proofs may justify optimization; **never trust a decorative annotation to remove observable foreign effects**.
- Retain ordinary strict numeric semantics as the default; no silent unsafe numerical transform for performance-score reasons.

### Hard gates

1. Differential strict and approved relaxed-reference arithmetic across NaNs, infinities, signed zero, subnormals, overflow/saturation and target/vector lanes.
2. Public O0/O1/O2 executable programs plus backend IR/disassembly confirmation, with validated float-policy metadata.
3. Real AEP-like DSP kernels showing correctness, code size, compile-time and performance deltas against specified baselines; no blanket zero-cost claim.
4. Negative compiler-stage/verifier controls rejecting illegal alias, effect and lifetime assumptions.
5. Appropriate host SIMD versus scalar fallback evidence; target-specific unsupported behavior must fail closed.

**Not included automatically:** general target migration, SH-4, self-hosting, arbitrary new floating syntax without approval, or unbounded codegen research detached from observable applications.

## 4.4 Surge 12 - Freestanding and general allocator architecture

### Required implementation outcomes

- Qualify a *true* no-OS/freestanding execution profile on a **selected available non-SH-4 target** (hardware board or credible executed emulator with precisely documented boot/ABI conditions). Selection follows a real toolchain/environment probe and an explicit target decision.
- Provide startup, linker, entry, runtime dependency profile, panic/error, initialization and teardown, static data and low-level memory facilities, with no unused libc/GLib/GObject/COM or threads.
- Generalize allocation policy for native Classes, records, generic containers, async frames and selected callbacks: heap, arena/region, pool, caller/static and custom allocators as supported, with provenance, alignment, failure, owner/region lifetime and release authority.
- Qualify allocation-failure recovery where allowed; no hidden fallback or cross-region escape. Retain deterministic destruction and compiler-owned storage semantics.
- Introduce compiler-checked low-level `[Allocator(...)]`, `[Repr(C)]`, alignment or `[Interrupt]` contracts if their design gates are satisfied; reject impossible layout and target policies.
- Define explicit volatile and atomic hardware access semantics, including ordering and lowering, on qualified targets; a mapped host-memory probe is not equivalent to hardware device qualification.

### Hard gates

1. **Actual executed no-OS program** on the selected non-SH-4 target; Linux `-nostdlib` alone is not enough.
2. Exact object/layout/ABI, linker map, startup trace, RAM/ROM use and no-unused-runtime dependency inventory.
3. Owner/allocator exhaustion, wrong-alignment, region escape, destructor timing and mixed allocation-policy negative tests.
4. Embedded-native execution plus hosted regression compatibility and independent IR mutation checks.
5. Qualified no-OS code/data size and performance observations, not only the ability to emit an object file.

**Explicitly out:** SuperH/SH-4, Dreamcast target qualification, and self-hosting. If no suitable physical or emulated target can execute, report the real blocker and arrange a target decision; do not invent a PASS.

## 4.5 Surge 13 - Concurrency, monitors and advanced runtime

### Required implementation outcomes

- Atomically safe opt-in shared/weak lifetime operations where cross-thread owners are supported; preserve the unique-default and separately declared intrusive/boxed-sharing distinction.
- Native threading/synchronization primitives, thread spawning/joining, `Send`-like transfer/proof policy as needed, lock memory ordering, data-race rejection where statically provable, and clear unsafe/foreign boundaries.
- Threaded/parallel executor and async task migration, cancellation, owner/frame lifetime, shutdown and structured operation semantics; preserve working cooperative/liburing profiles.
- Real TCP/UDP and higher-level network I/O with cancellation, partial transfer, backpressure, errors and safe buffer ownership; no assumption that timer success proves networking.
- **Policy attribute work:** design/qualify `[Monitor]` (or agreed `[Mutex]` alias), `[ThreadBound]`, and a bounded `[Singleton]` scope, including `[Shared, Monitor, Singleton]` composition where the contract is demonstrably safe.
- Evaluate `[Actor]` separately. It becomes a required implementation only after explicit semantic approval; an actor is not a disguised monitor or unqualified task scheduler.
- Design COM apartment/agility and GObject thread-affinity requirements for later adapters; actual foreign COM ABI execution is chiefly Surge 14.

### Hard gates

1. Real concurrent applications using qualified threads/executors, not single-thread simulated interleavings alone.
2. Exactly-once shared teardown and weak expiration/upgrade under stress; suitable atomics/memory-model checks and available race detection.
3. Monitor release on return/checked exception; protected mutable borrow escape refusal; nested/reentrant call policies; no implicit await under lock.
4. Executed TCP/UDP client/server and cancellation/partial-I/O tests with ownership and shutdown evidence.
5. Composition tests of shared/intrusive/boxed policies and selected foreign callback paths with no mandatory runtime costs for unused features.

**No blanket claims:** a refcount is not a mutex; a monitor does not prove deadlock freedom; a COM apartment rule is not satisfied by locking; atomic counters do not make arbitrary Class fields thread-safe.

## 4.6 Surge 14 - Semantic attributes, foreign ABI, tooling and release

Surge 14 has **two coordinated acceptance gates, 14A and 14B**, within one large potentially multi-session campaign. An ABI implementation is not a release until integrated and installed independently.

### 14A: Attribute substrate and foreign interfaces

**Policy/semantic integration**

- Complete the canonical typed attribute registry, supported placement, argument validation, inheritance/specialization rules, conflicts and compiler-policy introspection.
- Implement the agreed **`[Shared]` default intrusive Class** policy and **`shared T` non-intrusive boxed** spelling for supported `T`, preserving existing `Shared<T>`/`Weak<T>` behavior or providing an explicitly tested migration. Resolve copy/clone, weak anchor, allocator and thread rules without changing unique Classes by accident.
- Integrate approved `[CImport]`/`[CExport]`, `[GObjectImport]`/`[GObjectExport]`, `[COMImport]`/`[COMExport]`; policy effects must be recognized by the checked frontend and native/foreign ABI lowering, not by independent unverified source rewriting.
- Test `Shared + Monitor + Singleton` and relevant multi-export combinations *if approved and representable*. Invalid combinations must be rejected with meaningful diagnostics.

**C and GObject**

- Broaden C typed contracts: unions, callbacks, ownership, nullability, errors, constants/macros/header expressions and relevant target ABIs.
- Deliver **real native Astra-to-GObject export** with generated GType-aware adapters, property/signal bridges, GIR and typelib metadata, stable foreign wrapper identity and proven ref/weak/closure/cycle/shutdown translation. Native Class layout remains independent.
- Qualify independent C/GObject producers and consumers, proper GLib/GObject dependencies only when used, and selected broad GIR import/export profiles.

**COM / DirectX-style support - newly added planning objective**

- Implement a selected **in-process `IUnknown` interface profile** via `[COMImport]` and `[COMExport]`: exact target calling conventions and vtable order, IID/GUID, canonical `IUnknown` identity across views, `QueryInterface`/`AddRef`/`Release`, `HRESULT` status/error/out mapping, ownership and no-exception-unwind boundaries.
- Qualify *independently compiled* COM producer and consumer interactions in a real compatible host/runtime environment. For native Windows COM, **Windows execution or equivalently justified executing compatibility environment is required**; Linux source inspection, layout sketches or emitted objects alone do not qualify it.
- Keep interface exposure separate from class-factory registration/activation, type-library/IDL import/export, aggregation, apartment marshalling, out-of-process servers, WinRT and connection points. Those advanced subfamilies require their own approved scopes; not a consequence of simple working `IUnknown`.
- Ensure `[Shared]` native identity and lifetime bridge to COM's strong references without assuming a native Astra object is a physical COM object. Combined C/COM/GObject wrappers may have different pointer identities but must share one coherent underlying native-owner identity and teardown policy.

**Explicit new-scope authorization boundary:** The COM goal is accepted as a **roadmap objective** here. It was not part of the already submitted Surge 10 work and must be included in a future Git-pinned engineering packet with the chosen COM host/ABI and appropriate user approvals. If a usable execution host is absent, no COM PASS is claimed; retain an exact environment blocker rather than silently weakening the gate.

### 14B: Developer tooling, release integration and distribution

- Complete package/dependency management, module compatibility/versioning, reusable compiler/runtime library layout, source formatter and a functional language server/editor integration.
- Improve debug/type/provenance support for source expressions, aggregates, ownership, optimized code, closures/async frames and selected foreign-boundary stacks.
- Make policy costs inspectable, potentially through a source-based semantic explanation tool; exact `--explain-semantics` CLI is a candidate until approved.
- Provide independently installable, reproducible compiler/runtime distributions and examples, no dependency on the developer's private directory structure, and a supported command-line build/link/install path.
- Perform a **fresh broad regression registry and full accumulated application corpus** appropriate to the supported profiles, plus cross-feature new programs using owned aggregates, threading, allocator policies, DSP, C/GObject/COM, packages and debugging.
- Produce a truthful, feature-by-feature **Founding Bible conformance matrix**, mapping every mandatory/optional statement to implemented/qualified/experimental/missing/deferred and evidence links; preserve historical results without relabeling.
- Explicitly cover the old LAZY-1 Q4 historical status. If independently requalified in a separately authorized campaign, record the new provenance; otherwise leave `HELD/INCOMPLETE` rather than hiding it in another green test set.

### Hard gates

1. Independently compiled, executing C, COM and GObject foreign clients across their **distinct ABIs**, with identity and cleanup evidence for chosen supported combinations.
2. Language-server/editor, package installation/use, readable diagnostics, source debugging and documented policy metadata exercised by actual users/tests.
3. Fresh cross-feature compiler, application, numerical, async/concurrency, sanitizer/memory and target-qualification suite appropriate to declared release platforms.
4. Independent out-of-tree install and reproduction of public compiler/runtime builds.
5. Exact full-feature candidate conformance/status matrix. A missing **required** capability cannot be relabeled PASS by narrowing the category after the fact.

An advanced optional concept such as general reactive `[Tracked]` graphs, arbitrary COM activation or WinRT is not automatically required for developer-preview PASS unless later explicitly accepted into the selected release profile. It must still be assessed and recorded rather than silently disappearing.

---

# 5. Attribute adoption dependency graph and design gates

## 5.1 Resolve once; reuse across features

| Shared dependency | Needed by | Earliest useful investigation | Implementation/evidence gate |
| --- | --- | --- | --- |
| Typed attribute semantic identities and conflict engine | `[Shared]`, `[Monitor]`, singleton, C/COM/GObject, effects, layout | Surge 10 inspection; Surge 11 minimal substrate | Surge 14 must integrate all accepted policies |
| Strong/weak ownership representation and memory order | Intrusive `[Shared]`, `shared T`, threading, foreign ref adapters | Surges 11-12 design; Surge 13 atomic implementation | Surge 13 real threading; Surge 14 native/foreign ABI composition |
| Lock/loan/effect/callable authority | `[Monitor]`, `[Actor]`, `[ThreadBound]`, callbacks, async, Singleton | Surge 13 | Negative escapes, exception paths, no under-lock await, cross-thread safety |
| Allocator provenance and target layout | `[Allocator]`, `[Align]`, `[Repr(C)]`, interrupt contexts | Surge 12 | Real target/layout/allocator tests |
| Verified effect/alias facts | `[Pure]`, `NoEscape`, optimizer policies | Surge 11 | Formal negative controls + emitted IR/machine code and behavioral equivalence |
| Native identity to adapter identity map | GObject export, COM export, combined C/COM/GObject | Surge 14A | Independent foreign clients; weak/finalization/cycles |
| Property cache, dependency/invalidation, observable effects | `[Lazy]`, `[Tracked]`, `[Observable]`, `[Memoized]` | Surge 10 property semantics; later design review | First-success core required; reactive graph extensions remain proposals until ratified |

## 5.2 Explicit pending decisions (not yet frozen grammar)

The October Bible's register preserves the canonical question IDs. The roadmap collects them into engineering decision bundles:

| Decision bundle | Bible IDs | Earliest closure target |
| --- | --- | --- |
| Attribute grammar/registry, namespacing, precedence, inheritance and policy inspection | `ATTR-01..03`, `META-01` | Substrate planned ahead of Surge 14; finish in Surge 14 |
| Intrusive/boxed sharing mechanics, explicit versus implicit retention, weak control, migration | `SHARE-01..05` | Surge 13 lifetime contract; Surge 14 surface/interop contract |
| Monitor/mutex name, reentrancy, await/callbacks, singleton scope and actor mailbox | `MON-01..03`, `ACT-01`, `SING-01..02` | Surge 13 |
| C boundary and COM reference/identity/ABI/host | `CABI-01..02`, `COM-01..06` | Surge 14A, with platform selected explicitly |
| Native/GObject dual reference identities and metadata export | `GOBJ-01..04` | Surge 14A |
| Cache/graph/invalidation/notification and memoization | `PROP-01..04` | Surge 10 for bounded property forms; graph policy optional gated later |
| `NoEscape`, interrupt, trusted foreign and target proofs | `META-02` | Surge 11, 12 and 14 as relevant |

An agreed *direction* is enough to plan implementation, **not** enough to guess parameters, ABI symbols, retain-on-copy semantics or the actual allowed combinations. Examples do not close these questions.

---

# 6. Integration and release readiness

## 6.1 Profile matrix that must remain distinct

| Profile | Required claim and test |
| --- | --- |
| Hosted GNU x86-64 | Exact current public O0/O1/O2, generated native apps, memory and ABI tests |
| Linux no-libc/CRT | Existing observed execution; not a no-OS embedded system |
| Selected non-SH-4 no-OS | Surge 12 independent boot/execution and dependency/size evidence |
| SIMD/DSP strict or explicitly relaxed | Surge 11 numerical/reference, generated-code, throughput/latency evidence |
| Threaded + TCP/UDP | Surge 13 actual concurrency/network execution and lifetime/race tests |
| GObject/GLib | Surge 14 foreign adapter and dependent runtime tests; optional otherwise |
| Windows/COM | Surge 14 chosen real compatible host/ABI, executing producer + consumer; not extrapolated from Linux |
| Other target object-only | Honest OBJECT_ONLY, never executed-target PASS |
| SH-4/Dreamcast | Explicitly **DEFERRED**; not a condition for Surges 10-14 |
| Self-hosted Stage 1/2 | Explicitly **DEFERRED**; Stage 0 Vala remains acceptable for this release candidate |

## 6.2 Definition of a full-feature candidate

A candidate release is ready only when:

1. Every **required** selected Founding Bible capability has an executable, documented and evidence-backed implementation in declared supported domains; known restrictions are visible.
2. Native source review remains ordinary: no unnecessary sigils, duplicate ownership boilerplate or implicitly hidden expensive foreign/runtime behavior.
3. The compiler and runtime install and run outside the development tree, including public optimization, source debugging, package dependency resolution and usable editor tooling.
4. Real numerical, foreign ABI, concurrent, hosted and chosen non-SH-4 bare-metal profiles satisfy their own distinct tests.
5. Comprehensive fresh regressions, the cumulative application corpus and strong negative/verifier/memory checks pass. Historical PARTIALs remain archived honestly.
6. A release manifest records compiler/source/toolchain/library identities, build recipes, supported profiles, generated output hashes, license/dependency obligations and upgrade/compatibility policy.
7. The conformance review explicitly distinguishes **mandatory**, **optional/candidate**, and **deferred** Bible content; it never declares the whole Bible finished because some optional dream remains undefined.

This is **not** automatically Astra 1.0. Version 1.0 would additionally justify stable public compatibility commitments and operational maintenance across independent adopters.

## 6.3 Application and performance witnesses

Use real programs, not only syntax probes. Retain the A01-A72 cumulative historical identities; Surge 10 proposes A73-A84. For later surges choose independent new workloads suited to the new semantics rather than promising counts without corresponding feature coverage.

Performance review records code size, compile time, allocations, runtime and memory use alongside correctness. Fast-math results report numerical policy, precision assumptions and possible divergences. Shared/monitor/singleton/foreign attributes must expose lock/refcount/adapter costs to the reviewer. Optimizer `PASS` is not inferred from LLVM generating any optimized code; prove actual semantics-preserving transformations.

## 6.4 Native Codex engineering protocol

- Normal interactive `codex`, project/global `AGENTS.md`, installed `$pm-next`; `pm-codex-submission/1` tasks pinned to the *actual current Git HEAD*, with `codex-project.json` ID `astra`.
- Generated builds routed outside the repository (`~/Workspace/codex/work/astra/build/` or the current project-approved environment variables); protect preexisting dirty, untracked, ignored user content, archive branch, sibling worktree and hooks.
- Large integrated campaigns with source-first probes, explicit acceptance matrices, application witnesses, IR mutation controls and reproducible evidence.
- **Finish or resume** when safe: continue implementation/debugging instead of voluntarily publishing PARTIAL because a hard subsystem remains. If a genuine safety/permission/environment/resource/session blocker intervenes, preserve WIP and exact continuation instructions. No imagined indefinitely unattended execution.
- Obtain user approval for incompatible/breaking semantics, new high-impact ABI/platform assumptions or modifying pre-existing user-owned files. Don't silently rewrite historical test meaning.
- `PASS` means all required gates passed; `PARTIAL` is an honest result for actual incompleteness/blockers, not a green label for the easiest subset. An unavailable Windows/COM host cannot yield a COM PASS.
- Keep each campaign's own evidence immutable, including the historical LAZY-1 Q4 `HELD` state.

---

# 7. Continuity of the original 35 questions

The full original question text is preserved in Roadmap v1.0, section 6. The table below **updates status and next action**, not the historical wording or the meaning of an older qualification result.

| ID | Original topic | Position on 18 Oct 2026 / follow-on |
| --- | --- | --- |
| Q01 | Async syntax/task values | Native task model accepted in bounded profiles; broader generators/callables Surge 10/13 |
| Q02 | Completion/cancellation | Real scoped cooperative + liburing operations; threaded shutdown Surge 13 |
| Q03 | Borrows across suspension | Finite proof; generalized aggregate/property and thread migration Surge 10/13 |
| Q04 | Frame/executor storage | Finite executor; allocator substitution Surge 12, threaded executor Surge 13 |
| Q05 | Errors in sync/async | Checked Class exceptions exist; broaden foreign/concurrency mapping 13/14 |
| Q06 | Callable captures/foreign retention | Owning closures and C retained callbacks work in selected profiles; generalized signatures/threads 13/14 |
| Q07 | Allocated unique Classes | Accepted bounded; general allocation policy Surge 12 |
| Q08 | Owned child fields/extraction | Finite owned child and Bag extraction; general graph/aggregate Surge 10 |
| Q09 | Declaration lifetime policy | **`[Shared]` intrusive default newly agreed, NOT implemented**; Surges 13/14 |
| Q10 | Derived owned structs | Finite multi-owner prefix rollback; recursive/generic/enum composition Surge 10 |
| Q11 | Generic borrow/owner locals | Qualified finite generics, Bag; generalized types/iterators Surge 10 |
| Q12 | Nullability/refinement | Explicit opt-in finite; broader flow Surge 10; default unchanged without approval |
| Q13 | Recoverable allocation | Finite arenas/checks; general failure+allocator policies Surge 12 |
| Q14 | Shared/weak | Existing opt-in boxed `Shared<T>` single-threaded; intrusive/atomic thread-safe semantics 13/14 |
| Q15 | Inheritance/interfaces/RTTI | Native interfaces finite; opt-in reflection/multi-ABI metadata 10/14 |
| Q16 | Lazy cache/failure | Finite owning lazy delivered; old Q4 **HELD**; general property/caching 10/14 |
| Q17 | Property transfer/borrow | Finite owning/virtual; broader typed/generic/effect composition Surge 10 |
| Q18 | GObject/GIR lifetime | Import subset delivered; true native export & unified COM/C/GObject adapters Surge 14 |
| Q19 | Owned text/substrings | Owned snapshots/builders accepted; broader Unicode/value text Surge 10 |
| Q20 | Container growth/invalidation | Finite Bag accepted; generic/iterable/move-only element breadth Surge 10 |
| Q21 | External bytes/formatting | Bulk I/O and checked text work; further portability/general ABI Surge 10/14 |
| Q22 | Wider integers/size | i64/u64/isize/usize accepted host; broader vector/target portability 11/12 |
| Q23 | Public optimization | O0/O1/O2 accepted; semantic FP and optimizer-derived proofs Surge 11 |
| Q24 | C ABI breadth | Selected POD/typed callback accepted; C/COM/GObject ABI breadth Surge 14 |
| Q25 | Allocator authority | Finite arena; broad allocator/region/frame authority Surge 12 |
| Q26 | Embedded target/hardware | Linux no-libc + object-only AArch64; actual non-SH-4 no-OS Surge 12 |
| Q27 | SIMD/FP breadth | f64/i64/u64 vector2/saturation finite; full DSP/FP policies Surge 11 |
| Q28 | Modules/separate compilation | Versioned native linkage exists; packaging/stable library workflows Surge 14 |
| Q29 | Tooling/provenance | Formatter/-g initial; LSP/optimizer debug/package Surge 14 |
| Q30 | Named alternatives/control flow | Finite enums/loops; owning enum+stateful iterator Surge 10 |
| Q31 | Comparison chains | Accepted finite, with once-only/NaN tests; retain regression behavior |
| Q32 | `with` receivers | Accepted qualified construct; broader owner/field composition Surge 10 |
| Q33 | Regex | Optional candidate, provider/dialect/runtime cost not frozen; assess Surge 10/14 |
| Q34 | Inference/immutability | Local inference delivered; broader generic inference and immutable bindings require decision, Surge 10 |
| Q35 | Release/bootstrap/performance | Developer release candidate Surge 14; **self-hosting intentionally DEFERRED** |

---

# 8. Provenance, revision history and next decisions

## 8.1 Editorial provenance

- **B1** - `ASTRA_FOUNDING_BIBLE_2026-10-18.md` (October 18 canonical edition, historical §§0-68 preserved; attribute/foreign ABI §§69-82 newly added).
- **B2** - `ASTRA_ATTRIBUTE_POLICY_AMENDMENT_2026-10-18.md` (exact appended text of Bible §§69-82; statuses and open `ATTR`, `SHARE`, `MON`, `ACT`, `SING`, `CABI`, `COM`, `GOBJ`, `PROP`, `META` question families).
- **R1** - `ASTRA_VISION_AND_ROADMAP_v1.0_2026-09-27.md` (historical planning reference, Q01-Q35 original wording, historical OWN-SWAP-era status; untouched).
- **E9** - `astra-report-current(20261018-005333).zip`, reported `ASTRA-SYSTEMS-DSP-SURGE-9` PASS, accepted HEAD `959c47cb31cc7847150752ab26615545953a3400`; evidence of finite S1-S7, not general embedded support.
- **S10** - `ASTRA-LANGUAGE-GENERALIZATION-SURGE-10-SUBMISSION.zip`, already prepared against E9's HEAD, with G1-G9 requirements and A73-A84. **Submission is not execution.**
- **D18** - October 18 user/assistant design decisions and the explicit consolidated five-surge program, including new COM import/export, intrusive `[Shared]`, deferred SH-4 and self-hosting.

No independent live Git checkout inspection, compiler requalification, new COM/Windows execution or reinterpretation of historical test receipts was performed for this roadmap edition.

## 8.2 Revision record

| Edition | Meaning |
| --- | --- |
| **v1.0 - 2026-09-27** | Founding vision; OWN-SWAP baseline; seven-track plan and Q01-Q35; preserved unchanged as historical source. |
| **v2.0 - 2026-10-18** | Updates to Surge 9 accepted baseline, Surge 10 in-flight status, consolidated Surges 10-14 execution plan, new attribute/default-sharing semantics, COM import/export and multi-ABI adapters, clear release and qualification gates. No compiler source change. |

## 8.3 Immediate next actions

1. **Do not change Surge 10's already submitted task in place.** Obtain its actual acceptance report and final Git commit first.
2. Before preparing the next Git-pinned task, audit accepted Surge 10 output against G1-G9, metadata/attribute reuse opportunities, and current repository source.
3. Prepare Surge 11 with numerical/optimizer/effect proof, carrying the attribute-policy dependency forward without inventing already-ratified syntax.
4. Plan early evidence for a real non-SH-4 no-OS execution target (Surge 12) and a usable COM host/ABI (Surge 14); negotiate required hardware/toolchain access rather than waiting until publication day.
5. Keep `ATTR-01..03`, `SHARE-01..05`, `COM-01..06` and other October Bible open design records visible until explicit acceptance/ADR closure.

**Founding engineering contract reaffirmed:** Make sophisticated systems programming look ordinary. Native first; compatibility at explicit boundaries. Derive policy consequences once and make refcounts, locks, adapters and allocation costs visible. No speculative PASS, no premature self-hosting, no SH-4 detour.

*Made by Ria and Pim. 💙🖤*
