> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# Q11E: one incoming generic owner moved into one named local

Status: user-approved choice A and the five specified fixture replacements,
2026-10-15. Exact user decision: `A, fixtures yes.` Implementation and its
independent acceptance gates follow this design for `ASTRA-GEN-OWN-2D-OWNER-LOCAL-1`.
Q11 remains OPEN. ADRs 0094–0097 retain their historical contracts.

## Baseline and protected work

The live repository is `<historical-private-path>`, branch `astra-lazy-1`,
HEAD `054debde593713e1613885a51ed0063cd32999de`, tree
`a0bfc23542273ba44e255bd872f6d5acd1475840`. Intake verified the matching ZIP
SHA-256 `7a979e3d6b517fb1431e46ef18a425c01e2d00869e118ed644151fc767d8fd6a`.
The initial index and tracked diff were empty. All 17 nonignored untracked files
were inventoried with byte hashes and modes; none overlaps this design or its
new baseline runner. Preserve those files, ignored outputs, the sibling CAD
worktree and archive ref `fbd2c16f4a86da2a68da1938af18492eef7bb24d`.
No active standard Git hook or configured hooksPath was found; no hook changed.

The completed Q11D staging directory, including its extra logs, was preserved
at `runtime/gen-own-2c-published-054debde5937` before ordinary intake prepared
`runtime/native-current`. All paths below are under
`<historical-private-path>` unless stated otherwise.

Revalidated Meson source routing and options: `build/` belongs to this checkout,
debug, `werror=true`, `b_pch=false`, `linux_async=false`. Replayed all 217 commands
from `ninja -C BUILD -t commands astrac`, serially with ccache disabled, without
cleaning or touching source files. Then built the four existing contract targets.
The compiler SHA-256 is
`2f63d596a163c54efbaa6db536bbf87d4208d2a1a999e36ac2f59011550c22ea`.
Tools: Meson 1.11.2, Ninja 1.13.2, Vala 0.56.19, GCC 16.2.1, LLVM 22.1.8,
Valgrind 3.27.1. Build replay took 83.44 seconds including contract compilation.

Fresh evidence, before semantic changes:

- `python3 tools/design/gen-own-2d/baseline.py BUILD RUNTIME/gen-own-2d-baseline`:
  95 commands passed: eight actual native programs with exact expected traces,
  seven stage dumps each, two parsed-but-rejected local programs and 18
  exit-1/empty-stdout/no-executable gates. Covers Q11A Resource/Class loans,
  Q11B consumption in both same-T storage orders, Q11C forwarding, Q11D results
  in both orders, and existing Resource/caller-backed Class result forwarding.
- `meson test -C BUILD --no-rebuild --num-processes 1 --print-errorlogs
  --logbase gen-own-2d-baseline-contracts gen-borrow-1-contracts
  gen-own-2a-contracts gen-own-2b-contracts gen-own-2c-contracts`:
  four registrations, 63 TAP subtests passed (9 + 9 + 17 + 28).
- Five exact historical fixture payloads listed below were separately checked
  through nine CLI routes each: 45 rejection/no-executable gates passed.
  Original fixture files were unchanged at that baseline checkpoint.

Evidence is in `runtime/native-current/gen-own-2d-{preflight.json,
baseline-build.json,baseline-build-commands.txt,baseline-build.log}`,
`gen-own-2d-baseline/{identity,checks}.json`, `gen-own-2d-historical-controls/checks.json`
and `build/meson-logs/gen-own-2d-baseline-contracts.{txt,json}`.
These results establish the existing boundary, not Q11E implementation,
new local-pointer acceptance, fresh O2/memory qualification or a full-suite result.

## Alternatives and proposed domain

| Choice | Work authorized by that choice |
| --- | --- |
| A: Resource + exact Class | One explicitly typed `owned T` local, preserving Resource, heap Class and caller-backed Class domains through the proof below. Recommended on the representation evidence; independent new mutation/native/memory gates must still pass. |
| B: Resource only | Same finite local shape, but Class actuals rejected during independent source/Core qualification. Existing Class consumers/results remain legal. No claim of Class-local support. |
| C: Hold | Keep semantics unchanged and retain this design/obstacle report. |

The local must initialize immediately from `move` of the single incoming owned
T, at one structural declaration outside transferring loops. The helper is
top-level, synchronous, native, nonthrowing, constrained by exactly the accepted
Ownable requirement; other inputs and the result are supported copied scalars
or void. Allow one completed Q11A loan and, optionally, one direct local-to-terminal
generic consuming site. Preserve current inference, never infer a new local type.
No generic owned result in a helper declaring this local, including
`return move local`. No second owner-local/formal, rearm, null/default initializer,
construction, escape, partial move, ownership recursion, result chain, generic
member/aggregate, adapter, async or throwing extension is authorized.

The parser already accepts the declaration: both void-local and owned-result-local
controls pass `--parse`; the exact prohibition is in
[`analyzer.vala`](../bootstrap/semantic/analyzer.vala), around line 2045. No grammar or
keyword change is needed.

## Lifetime and physical-storage argument

Let P be the original pointer/Resource handle, D its exact cleanup contract,
and I/L the incoming/local owner slots. A slot holds responsibility, not a new
object allocation. A legitimate nullable incoming owner remains logically owned;
runtime cleanup skips null. Generic source gains no null construction or test.

| Point | Incoming I | Local L | Current responsibility |
| --- | --- | --- | --- |
| Function entry | P, live | not initialized | I with D |
| Direct initialization | disarmed/null | same P, live | L with the identical D |
| Completed loan | disarmed | unchanged P | L; borrower owns no cleanup |
| Normal/early exit retaining L | disarmed | retired once | D(P), conditional on nonnull |
| Terminal call capture/commit | disarmed | disarmed at invocation | Exact callee formal receives P and D |

If an exit precedes the declaration or its block is not entered, I still owns
cleanup. If only one branch transfers L, the join is OWNED | MOVED; another use
rejects, while conditional normal cleanup acts only on the retained pointer.
Each lexical exit retires any live local in existing cleanup order. Borrow
capture and invocation both require the current owner, rejecting overlap in
either argument order. Fatal traps do not unwind; no exception/async cleanup
promise is introduced.

**The same nominal Class has two cleanup domains.**
[`GenericFunctionInstance`](../bootstrap/core/core-generics.vala), lines 110–155,
already keys definition + exact ordered types + heap-owned-formal ordinal.
The fresh `consume-mixed.instances` contains `consume<Counter>` instances #1
(caller-backed) and #2 (heap formal #0); `consume-reverse.instances` requests the
heap form first (#0) and caller-backed last (#2), still separately. Q11D's
`result-mixed`/`result-reverse` independently show the same split for results.
Borrow-only `loan<Counter>` shares an instance because it chooses no cleanup.

[`CoreInstanceCloner.contract()`](../bootstrap/core/generic-monomorphizer.vala),
lines 315–319, maps the canonical symbolic T cleanup using the marked incoming
formal's domain. A verified T local can use that same mapping: same T token,
same root incoming formal, same D, distinct slot. It must not derive heapness
from the Class name. Concrete Core verifies equality with the root contract
and instance domain after cloning, including the downstream terminal call.

Heap D runs the existing complete destructor/child chain then frees P once.
Caller-backed D runs that chain without freeing P; caller/ancestor storage
outlives this synchronous invocation. Resource D releases exactly the incoming
handle. No destination object storage, candidate allocation or Class value copy
is created. The scalar/void helper's existing `(owner PTR, scalars...) -> scalar/void`
signature has no result-candidate channel. The original caller already selected
the concrete ownership domain; no runtime discriminator, dictionary or ABI
change is needed.

[`SsaBuilder`](../bootstrap/ssa/ssa-builder.vala), lines 769–784, already lowers scalar
ownership transfer by assigning the source's current SSA value to the destination
and defining typed null for the source. It emits no object copy or allocation.
[`verify_object_cleanup_domains`](../bootstrap/ssa/ssa-verifier.vala), lines 974–1038,
reconstructs heap/caller-backed origins from incoming parameter contracts and
SSA edges. [`NativeBuilder`](../bootstrap/nabi/native-builder.vala), around line 112,
and the native compatibility verifier retain exact Class/heap correspondence.
Those authorities, plus new transfer mutations, are required evidence for A.

## Required extensions to existing authorities

1. **Checked identity.** `LocalSymbol.is_generic_owner` currently recognizes only
   incoming parameters (`symbols.vala:179`), and `CheckedOwnedLocalDeclaration`
   asserts concrete/buffer initializer shapes (`checked-nodes.vala:303–312`).
   Extend these with an exact incoming-owner source relationship for this local.
   Keep its `incoming_parameter` null: pretending it is another parameter would
   make Core entry construction acquire the same incoming owner twice. Validate
   T, shape, names, signature and uniqueness before constructing the declaration.
   Preserve the old rejection for helpers returning owned T, so Q11D's historical
   local-return case and diagnostic can remain unchanged.
2. **One structured ownership proof.** Extend `GenericOwnershipFlow`'s existing
   MOVE/ACQUIRE and finite transfer summary with the exact local destination.
   Register declaration-dependent initial facts: a new local cannot start OWNED
   before its acquisition (the current generic owner array defaults to OWNED).
   Track its scope retirement on normal exits. Compose the one incoming-to-local
   edge with the optional local-to-terminal edge in Q11C qualification; neither
   becomes an unqualified move or a new result edge. Keep the existing path-state
   evaluator and acyclic callee qualification, including unreachable-site gates.
   Semantic call-fragment copying in `generic-call-inference.vala` must preserve
   any added exact event identity. No second post-hoc liveness algorithm.
3. **Core independently reconstructs.** `builder.vala:650–674` already maps an
   owned declaration initialized by move to `CoreOwnershipTransfer`, checking
   distinct owners and equal cleanup. Reuse that node and parameterized cleanup.
   Core reconstructs the local relation from its own declaration/transfer graph;
   do not trust a Semantic eligibility bit. Verify one source acquisition,
   exactly one matching fresh local, exact T/D, scope, initialization and terminal
   restriction both before and after specialization. Extend tracked-owner
   handling beyond the present incoming-heap-only predicate.
4. **Caller-backed gates require a precise new proof.** Core currently rejects
   all nonheap Class transfers (`verifier.vala:1574`); CFG has the analogous gate
   (`cfg-verifier.vala:1412`). Permit only exact incoming-parameter-backed local
   transfer with identical type/cleanup, fresh destination and no destination
   ObjectStorage. CFG must reconstruct the incoming acquisition and ordered
   transfer from its own graph, not accept arbitrary lexical Class moves.
   `OwnershipFlow` already disarms the source and starts the destination
   (`ownership-flow.vala:392–400`); normal cleanup planning stays authoritative.
5. **Independent current-pointer evidence.** Existing SSA ownership events cover
   heap Classes and record-associated Resources; synchronous Resource/lexical
   locals do not all receive them (`persistent_owner`, `ssa-builder.vala:688`).
   The exact-pointer solver in `ssa-exceptions.vala:99–137` currently activates
   for owning records and heap result owners. Extend these existing authorities
   to the new local transfer pair in all approved domains. Require the exact
   live source pointer, adjacent matched MOVE/ACQUIRE, source disarm, unique
   acquisition and exact cleanup/call operand on every normal edge. Owner events
   remain verifier metadata erased by LLVM lowering, not runtime owner tags.

The physical representation supports A; the listed source/verification gates
are genuine implementation work. If any cannot be enforced without dynamic
provenance or another ABI, stop affected implementation and request B/C. Neither
approval nor existing baseline traces count as passing the new gates.

## Separate historical fixture decision

These five baseline rejections become legal even when uninstantiated.
The user separately approved replacing only their obsolete single-local rejection with a
second-owner-local rejection, preserving exit-1/no-executable checking. Each
Python replacement appends `owned T second = move <first-local>;` immediately
after the existing local; the Q11C terminal call stays after that rejected
declaration. For the Vala test, replace only the `"move v"` loop entry with a
separate two-local rejection; retain copy and null rejection entries.

| File and exact case | Baseline expected substring | Approved expected substring |
| --- | --- | --- |
| `tests/gen-buffer-1/negative.py`: `ownable-local` | `generic owned locals` | unchanged |
| `tests/gen-borrow-1/negative.py`: `owned-local-T` | `generic owned locals` | unchanged |
| `tests/gen-own-2a/negative.py`: `generic-owner-local` | `generic owned locals and plain Ownable T locals` | `generic owned locals require one fresh local` |
| `tests/gen-own-2b/negative.py`: `intermediate-owned-local` | `generic owned locals and plain Ownable T locals` | `generic owned locals require one fresh local` |
| `tests/gen-own/semantic.vala`: `positions`, only `"move v"` | `generic owned locals` | unchanged |

Approved full new structural diagnostic:
`generic owned locals require one fresh local initialized by direct move of the single incoming owned T`.
This also retains the broad substring for existing copy/null controls. Add new
positive witnesses for the now-legal single-local forms, and new independent
local-return rejection coverage. Do not edit `tests/gen-own-2c/negative.py`'s
`generic-local` case. If another fixture conflict appears, seek separate consent.
The five replacements are applied under the explicit `A, fixtures yes.` decision;
intake alone supplied no authorization. Q11D's fixture remains unchanged.

## Acceptance after the decisions

Create `tests/gen-own-2d/` with scope/early exits, completed borrow, conditional
retention/terminal transfer, scalar neighbors, exact Resource handles and approved
Class domains in both request/declaration orders. Include empty/no-deinit,
derived/Q08-child and nullable-incoming witnesses without new generic null syntax.
Mutate and restore Checked/Core source/type/cleanup/domain/acquisition evidence,
CFG transfer/capture/retirement, SSA current pointer/event/cleanup and native origin
plans. Valid restoration must reverify independently after every rejection.

Then compare actual native and independently optimized O2 traces/pointers; run
unsuppressed standard-allocator Valgrind separately from free-count interposition.
Controlled leak/double-release detectors must detect their faults, suppress an
unsafe second host free and rerun the restored positive. Retain selected Q11A–D,
Resource, copy-generics, Q08, Q10B, object, virtual-async and lazy guardrails.
The packet's `tests/struct-move-1b/` path is absent; current Q10B fixtures and
recipe are under `tests/struct-move-1/`, as its README documents.

Only after approved implementation and evidence: add the next ADR, update active
language/IR/capability/roadmap scope, commit explicit task-owned paths with normal
hooks, and publish through the installed skill. No full registry, LAZY Q4, CAD,
real Linux/liburing, GUI/hardware or storage cleanup is included. Future
application-facing work is a separately pinned owning collection requirement
review (GEN-MEMBER-1/CONTAINER-1 and TEXT-OWN-1), not extra implementation here.
