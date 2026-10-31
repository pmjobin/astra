> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# ADR 0100: Concrete indexed heap-Class owners with explicit growth

Status: **User-approved Q20A option A.** 2026-10-15. Exact reply:
`1. Approve A — implement the documented finite Q20A growth contract.`
This is the design gate for ASTRA-CONTAINER-1A-HEAP-CLASS-GROWTH-1. Approval
preceded semantic implementation. The proof below specifies the compiler work
and its acceptance obligations; executed implementation evidence is recorded in
CONTAINER-1A validation.
Q20 beyond this subset and GEN-MEMBER-1A remain open.

## Verified starting point

Repository `<historical-private-path>`, branch `astra-lazy-1`, HEAD
`f431acaa775da1e4c0d3732d790509aeab5248fd`, tree
`b63bcbed3e54ff20cbd6f74d53d121e717cec030`. Index and tracked worktree were
clean. All 17 pre-existing untracked files are protected by SHA256, mode,
uid/gid and size in external `runtime/native-current/container-1a-preflight.json`.
That record also inventories 394,443 ignored files without deleting or adopting
historical builds. No active Git hook exists at the default hooks path and no
core.hooksPath override is configured; normal hooks remain enabled. Archive tip
`fbd2c16f4a86da2a68da1938af18492eef7bb24d` and sibling worktree tip
`a1fadc5c052e82ae464268787f617252998c24be` match the submission.
The completed predecessor runtime was preserved intact as
`runtime/native-published-text-own-1a-20261015T133910Z` before validated intake.

Fresh `CCACHE_DISABLE=1 tests/text-own-1a/verify.sh regressions` passed:
13 registrations, including 93 TAP subtests across 10 TAP registrations.
The application registration executed 74 commands, 15 unsuppressed Valgrind
runs, native/O2 parity and seven unchanged rejection probes. The Q19A execution
registration executed 366 commands and 52 unsuppressed memory runs, including
valid independent byte snapshots, malformed checked errors and fatal controls.
These are baseline results, not Q20A growth acceptance.

The new portable baseline recipe
passed 93 additional command checks and six unsuppressed Valgrind executions.
It executes numeric descriptor swap/owned-result transport, fixed-array slice,
zeroed buffer replacement, and two independent Q19A owners moved into concrete
child fields. Normal and early child exits both print exactly
`drop pair\ndrop second\ndrop first\n`, with zero live blocks/errors. Both
ordinary native and independently emitted `opt -passes=default<O2>` / `llc -O2`
binaries execute and agree. All six compiler-stage dumps are retained.

Class-element and escaping-buffer-view probes parse, then refuse at semantic
checking. Generic class and owned generic field probes refuse in the parser;
those are not lifetime proofs. Separate duplicate-owner, use-after-move and
double-release controls pass parsing, Checked and Core, then refuse at CFG
ownership flow and all later requested outputs. No negative fixture changed.
Numeric replacement is not reserve and does not preserve old contents.

External Meson routing was rechecked: this source root, `debug`, `werror=true`,
`b_pch=false`, `linux_async=false`, serial compilation, ccache disabled.
Compiler SHA256 `d696c00771291255377a749e21b635314a503dda02cfbc7edfea1e7a20577d42`;
host-entry emitter `158aa1ebabf67d8e208d451c99d3d25d0ea6c4ab8fdc8d3cb510bbe23296b7db`.
Meson 1.11.2, Ninja 1.13.2, Vala 0.56.19, GCC 16.2.1, LLVM 22.1.8,
Valgrind 3.27.1; hosted GNU x86-64 LP64 only. Fresh logs are under external
`runtime/native-current/container-1a-*` and `build/meson-logs/text-own-*`.

## Source authority and alternatives

| Existing authority | Consequence for Q20A |
| --- | --- |
| Application D01–D08, [current source](../../tests/app-diag-collection-0/current.astra), [noncompiling proposal](../../tests/app-diag-collection-0/desired.spec.txt) | Two named child fields work; indexed owner storage and growth do not exist. |
| [Buffer eligibility](../../bootstrap/semantic/buffer-elements.vala), [buffer shape](../../bootstrap/ssa/ssa-buffers.vala), [exchange](../language/owned-buffer-exchange.md) | Numeric PTR/I32 descriptors require copyable, zeroable, trivially destructible elements. Relaxing that rule would invalidate existing copy/drop proofs. |
| [Class storage](../../bootstrap/semantic/semantic-objects.vala), [origin solver](../../bootstrap/semantic/analyzer.vala), [child transfer](../../bootstrap/semantic/analyzer.vala) | Exact heap origin is already distinct from lexical/caller storage. Child assignment constrains incoming owner parameters to heap through the origin solver. Reuse and extend that mechanism for append. |
| [Child graph](../../bootstrap/semantic/owned-child-composition.vala), [field borrows](../../bootstrap/semantic/analyzer.vala) | Include owner-slot element edges in acyclicity and conservative containing-object overlap checks. Borrowed aliases cannot grant mutation authority during inspection. |
| [Core object storage](../../bootstrap/core/core-objects.vala), [CFG flow](../../bootstrap/cfg/ownership-flow.vala), [SSA object storage](../../bootstrap/ssa/ssa-objects.vala) | Transferable lifetime, heap allocation and exact nominal identity must survive independently at every phase. |
| [Q19A](0099-validated-utf8-message-factory.md), [text loans](../../bootstrap/core/core-text.vala) | Keep immutable snapshots and receiver-bound text loans; moving a pointer carrier does not move its snapshot or extend its lifetime. |
| [Allocator](../../bootstrap/backend/llvm/llvm-buffer-allocation.vala), [physical exchange proof](../../bootstrap/backend/llvm/llvm-buffer-exchange.vala), [native Class layout](../../bootstrap/nabi/native-classes.vala) | Reuse checked hosted allocation and actual-instruction binding patterns; add separate owner-slot layout and operation authority. No C-owned list or erased pointer API. |

**A — recommended:** a new finite owner-slot field type, concrete per exact
Class, with explicit growth and immediate borrowed inspection. No generic
Class/member machinery is required. The pointer-carrier transfer admits the
inductive proof below, provided all phase and physical checks are implemented.

**B — narrower:** fixed indexed slots would still require the new element,
heap, cleanup and loan authorities, while omitting only reserve's transfer
region. There is no demonstrated architectural reason to split growth yet;
this is not the recommendation. If a specific proof fails, present that blocker
and seek separate approval for CONTAINER-1B deferral; classify PARTIAL.

**C — hold:** review this design before implementation. A failed phase proof
does not authorize generic classes, pointer erasure, weaker borrows, copying
Class arrays, recoverable allocation or a silently narrower delivery.

## Proposed source contract (new syntax, not baseline-compiling)

```astra
class Diagnostics {
	owned Diagnostic[slots] entries;
	init() { this.entries = new Diagnostic[slots]; }
	bool reserve(int requested) { return this.entries.reserve(requested); }
	int count() { return len(this.entries); }
	int capacity() { return this.entries.capacity; }
	void append(owned Diagnostic entry) { this.entries.append(move entry); }
	bool render_at(int index) { return render_diagnostic(this.entries[index]); }
	deinit() { println("drop diagnostics"); }
}
// After forming first, second and third as distinct heap owners:
// if (!bag.reserve(2)) { return 81; }
// bag.append(move first); bag.append(move second);
// if (!bag.reserve(3)) { return 82; }
// bag.append(move third); bag.render_at(0); // also inspect indices 1 and 2
```

`[slots]` is a contextual type/allocation marker, producing an exact nominal
`OwnerSlotsType`, never SliceType/ArrayType or a generic Class instantiation.
Initially it is admitted only as an owned native Class field, at most one such
field per collection Class. Construction explicitly initializes an empty
descriptor once; there is no allocation until reserve. No descriptor copying,
replacement, extraction, direct release, swap, slice, raw address, local,
parameter, result, generic or foreign exposure is admitted. Collection methods
above are ordinary concrete Astra methods; only the storage operations are
typed compiler primitives. Existing method syntax has expression receivers
([CallExpressionSyntax](../../bootstrap/syntax/nodes.vala)); parser support for
the new marker is required. No compiler special case names Diagnostic or Text.

The element must be one exact nonpolymorphic native Class with established
heap cleanup and no inheritance. Scalars, readonly snapshots and existing
acyclic concrete child owners are permitted. Nested owner-slot containers,
Resources, records, lexical/caller instances, borrowed references, subtypes,
raw pointers and mixed element types are excluded. Extend existing heap-origin
constraints through append, including wrapper parameters; a lexical producer
must cause a conflict, never be relabeled heap. Test a second unrelated Class.

`len(store)` and `store.capacity` are readonly signed-I32 queries. They expose
no owner. `store.reserve(n)` returns bool, never consumes an element, and never
shrinks. Negative or unrepresentable requests return false before allocation
or mutation. A nonnegative request at or below capacity returns true without
allocation. A larger accepted request grows to exactly n. The maximum is
`min(INT32_MAX, SIZE_MAX / slot_width, PTRDIFF_MAX / slot_width)`; on the qualified
LP64 target this is INT32_MAX. Checked multiplication and complete extent
validation remain mandatory even where that bound makes overflow unreachable
from valid source. Test finite forged extents, not enormous allocations.

`store.append(move entry)` returns void and requires an initialized store,
`len < capacity` and a nonnull exact heap owner. Source should reserve and
check success before creating/transferring incoming owners. This is a strict
precondition API: a full store or null heap result traps fatally before the
primitive transfers ownership; it does not return false and destroy an entry.
There is no normal unsuccessful append. In a wrapper call the caller has
already transferred to the wrapper parameter; fatal-path unwind/recovery is
not promised. This limitation is part of the approval request. No allocation,
callback or throw occurs between acceptance, source disarm and count commit.
No implicit growth or consuming `append_or_drop(false)` behavior is added.

`store[index]` is accepted only as a direct borrowed exact-Class argument to
a synchronous nonthrowing concrete native free function returning void or a
copied scalar. Bounds check `0 <= index < len` before loading. Invalid dynamic
indices trap with no mutation; known-invalid constants may be diagnosed.
This is not a returned borrowed reference, persistent view or arbitrary Class
expression. No indexed assignment, move, release, field projection, extracted
local or method receiver is admitted. A helper can read metadata, compare
identities, and inspect/render nested Q19A message views within its call.
That subset suffices for a source loop over all occupied indices.

The call loan includes exact field, container, selected element, captured index
and call extent. From argument capture through invocation completion, reject
any potentially aliasing container/ancestor argument, move, release, reserve,
append or mutation, including effects nested in later arguments. Keep existing
conservative nominal overlap rather than inventing purity/effect inference.
Multiple element borrows are allowed; owning container aliases are excluded
from the same call. Helper Class parameters remain borrowed and cannot move,
release, retain or return the element. Text views cannot escape the helper.
No callback, closure, async suspension or C inspection channel is introduced.

## Representation and inductive unique-owner proof

The collection field owns `{base: PTR, len: I32, capacity: I32}`. On qualified
LP64 it occupies 16 bytes aligned to 8, with offsets 0/8/12, independently
checked against target data. The zero descriptor is `{null,0,0}`. Positive
capacity owns one separate zeroed allocation of capacity pointer slots, stride
8, alignment 8. Slots `[0,len)` each own one distinct nonnull exact-Class heap
lifetime; `[len,capacity)` are null and own nothing. Counts are not user-writable.
No per-element ownership tag, refcount, runtime identity table or destructor
pointer is stored: exact Class identity determines cleanup statically.

The steady invariant includes `0 <= len <= capacity`, exact allocation extent,
one backing owner, disjoint element rights and the acyclic child graph.

| Transition | Ownership argument |
| --- | --- |
| Empty initialize | Zero descriptor grants backing/element rights to nothing. Definite initialization still establishes field cleanup responsibility. |
| Append | Validate receiver, descriptor, capacity and nonnull heap input first. At index len the slot is empty by invariant. One indivisible transfer stores the carrier, disarms the sole input owner and publishes len+1. Because len < capacity <= INT32_MAX, increment is representable. No ordinary failure/call occurs inside commit. |
| Reserve rejection/no-op | Validate request/descriptor without writes or owner transfer. Return false for invalid requests, true for already-sufficient capacity. Existing elements, order and capacity are unchanged. |
| Growing reserve | Check the full byte extent; allocate a separate empty store before modifying old storage. At loop boundary i, new `[0,i)` owns old elements 0..i-1; old `[0,i)` is null; old `[i,len)` still owns the remainder; every other new slot is null. Move one carrier and clear its old slot in one internal transfer step. The primitive holds both backing rights and this split invariant exclusively. No callback, destructor, ordinary checked failure or observable descriptor read occurs inside. |
| Reserve completion | All live rights now belong to the new store in original order. Install the complete new descriptor in one language effect, then free the captured old empty backing exactly once without invoking element cleanup. No hardware/thread atomicity is claimed. Referent objects and nested message snapshots are never copied, relocated or reallocated. |
| Borrow | Select only an occupied slot after bounds proof; acquire no owner right. Exact lender/call exclusion prevents owner destruction or structural mutation until the call ends. |
| Drop | Existing user deinit runs first. At this field's established reverse field-cleanup position, retire slots len-1 down to 0: clear/disarm each slot, run its exact Class destructor/child epilogue, free its heap object once. Free backing once after all elements; zero the descriptor. Empty, early and checked exits share this cleanup contract. |

Transient duplicate machine pointer carriers during a commit are not two
semantic owners: the enclosing verified transfer region owns the one right.
Its sequence must not be exposed as independently copyable SSA values. Old
and new descriptors do not both acquire ordinary full-store cleanup duties.
The reserve loop's i supplies split-state proof, not a runtime registry. After
allocation, transfer/commit/free have no ordinary failure or user code. OOM
retains the established fatal trap, with no catchable result or fatal unwind
claim. Reserve does not call element destructors. Source deinit may perform
ordinary permitted operations before the automatic epilogue begins; the
epilogue itself has no source reentry route to the containing collection.

## Phase and ABI obligations required before acceptance

These are obligations to implement and independently falsify; a trusted flag,
runtime null check or LLVM's structural verifier alone cannot establish them.

| Boundary | Required new authority and deliberate corruption controls |
| --- | --- |
| Syntax / Checked -> Core | New concrete storage type and exact declaration/field identity; one empty initialization; heap origin constrained from every append caller, including uncalled/forwarding wrappers; acyclic slot-element edges; exact borrowed argument/call extent. Reject wrong Class, lexical origin, copied source, false field/index/lender or missing cleanup authority. |
| Core | Dedicated initialize/query/reserve/append/borrow/drop operations; stage-local exact Class/cleanup/field contracts; append input's unique live owner and checked noescape use. Verify against actual declarations. Mutate source owner, type, initialization and cleanup relation independently. |
| CFG | Dedicated effect regions and status continuations for reserve; reserve false/no-op edges retain the descriptor. Append acceptance dominates input disarm and count publication. Loan capture/invocation exclusion and existing owner-flow joins must survive. Mutate edges, owner reservation/disarm, lender and cleanup. |
| SSA | Separate owner-slot group PTR/I32/I32 with one origin, exact field place and typed move/borrow/reserve effects. Keep reserve's split invariant as a verified primitive region rather than admitting arbitrary user pointer loops. Validate all operands, effect order, input disarm, bounds/count/capacity group, cleanup coverage and exact call extent. Mutate each relation and independently restore/reverify. |
| Native | Add private owner-slots-v15 ABI capability only for programs requiring it; preserve prior program/version/layout behavior. Copy exact Class/field/destructor identities and group layout into native plans. Slot storage is not NativeSliceType or a public C type. Check actual SSA/native correspondence and reject erased Class, wrong extent/stride/destructor/count fields. |
| Actual LLVM | Emit per-exact-Class private typed operations, using the existing qualified calloc/free strategy with no global allocator change. Bind target-derived descriptor/slot layout, actual range/overflow branches, allocation-before-transfer, each loop load/store/old-slot clear, full descriptor commit, old backing free and reverse final cleanup to immutable operation plans. Verify their actual instructions/CFG/calls and reject changed guards, indices, receiver, disarm, commit order, destructor or free. Never execute corrupted IR. |

No Class object ABI, existing numeric array/slice API, Q07–Q11 generic behavior,
Q19A factory/error/text-loan contract, foreign boundary, async/LAZY facility or
public optimization flag changes. Programs that do not use owner slots acquire
no new runtime support. Retain all historical negative files and expectations;
`new Message[2]` still refuses. No permission to change a negative to positive
is requested by this proposal.

## Decision and acceptance boundary

The requested decision is **approve A as specified**, or hold C. B requires a
concrete growth blocker and a separately presented narrower scope. Approval of
A includes the contextual `[slots]` marker, exact typed storage primitives,
bool reserve, fatal append/index preconditions, call-only inspection subset
and private versioned ABI plan above. If implementing those proofs requires a
material change, return for review before making that change.

After approval, implement an adjacent ordinary Astra diagnostic application,
public buildable example and focused tests: 0/1/2/3 owners; real 2->3 backing
growth; stable independent identities and order; normal/early/checked cleanup;
unchanged café, combining accent, heart, empty and embedded-NUL snapshots;
same-capacity and rejected reserve; capacity/index/null/type/loan negatives;
each applicable phase mutation; real allocator/destructor observation; and
separate unmodified standard-allocator Valgrind execution. Execute ordinary
native and independently optimized O2 binaries and compare exact evidence.
Repeat the packet's affected regressions; no full historical registry.

The user approved A after reviewing this proposal and the fresh baseline.
No historical fixture changes were requested or authorized. PASS ultimately
requires measured growth and all lifetime proofs;
design-only or approved fixed-slot work can at most be PARTIAL.

## Implemented correspondence

The implementation preserves the approved source and failure contracts. Core,
CFG and SSA keep the descriptor in its exact containing field as an indivisible
typed operation group; they do not expose three independently copyable SSA
leaves or expand reserve into user-visible pointer operations. Reserve's bool
is an ordinary scalar result. Private LLVM helpers expand its split-ownership
region and bind the complete actual instruction/edge/operand sequence,
allocation calls, exact destructor and target-derived layout. Each verifier
owns its stage's identities after the predecessor model is retired.

The source marker is recognized only for a complete `[slots]` suffix on a Class
field. Numeric counts and constant arithmetic using an identifier `slots`
continue through existing numeric array/buffer checking. Construction remains
an ordinary allocation syntax node, interpreted as empty slots initialization
only at the exact constructor field assignment. No generic Class array rule
is relaxed.

The diagnostic integration revealed an existing declaration-order restriction:
CFG and SSA validated an owned child Class field before registering a later
library Class. They now defer that field's existing exact type/cleanup check to
the final child validation pass after all class descriptors are registered.
The type domain and final child checks remain intact. Relevant Q08 regressions
are included in the qualification recipe.

The append pointer proof reuses the established heap-owner dataflow, including
its control-edge current-pointer and exact acquisition checks. Matching a
forged append operand to a forged disarm is insufficient: both must correspond
to the authentic live owner. Dedicated corruption controls exercise this case.

The [guide](../language/owner-slots.md), [example](../../examples/diagnostic-slots/main.astra)
and [qualification recipe](../../tests/container-1a/verify.sh) describe the
implemented subset. Validation records actual outcomes and remaining limits;
the proposal and pre-approval evidence above remain part of the decision history.
