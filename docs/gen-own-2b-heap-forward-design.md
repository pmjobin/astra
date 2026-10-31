# GEN-OWN-2B: finite heap Class forwarding design

State: **Q11C-HEAP-FORWARD-NORESULT approved**, 2026-10-14. The user explicitly
answered “Approve the documented Q11C scope”, then separately “Approve these
seven replacements”. This document records the pre-implementation current-source
baseline and the concrete design reviewed before semantic edits.
Q11B authorizes direct heap consumption; it does not authorize this extension.
Q11 remains OPEN.

## Verified baseline

Intake selected `ASTRA-GEN-OWN-2B-HEAP-FORWARD-1-SUBMISSION.zip`, SHA-256
`d574e53099a735acc71f33437d17a3d87ccbceed008dc41ebc409960fa14de00`.
Live project astra, branch astra-lazy-1, HEAD
`a581c929415a61c2ed283a6115adfca8a47355ae`, tree
`223fad4c3a0ed608e4c38c15099e3d25b70925d9` match the packet.
Its six supplied production hashes and preceding report's byte count and SHA-256
match the actual files. The preceding report remains historical evidence.

Tracked/index state was clean before authoring. All 17 initial untracked files
were recorded by name, byte count, mode and SHA-256; none is a task edit target.
Ignored inventory identifies the historical build directory without traversing
its contents. No ignored output was removed or modified. Archive tip remains
`fbd2c16f4a86da2a68da1938af18492eef7bb24d`; sibling astra-cad-1 remains at
`a1fadc5c052e82ae464268787f617252998c24be`. Default Git hooks routing is retained.
The completed Q11B runtime was preserved by rename to
`runtime/native-completed-ASTRA-GEN-OWN-2A-HEAP-CLASS-1-a581c929` after intake
refused its evidence files; nothing was deleted.

The reusable external Meson build routes to this actual repository. Its strict
serial compiler/contract build returned 0 with debug, werror=true, b_pch=false,
linux_async=false and CCACHE_DISABLE=1. Existing Vala 0.56.19, GCC 16.2.1,
LLVM 22.1.8, Meson 1.11.2, Ninja 1.13.2, GLib/GObject 2.88.4 and Valgrind 3.27.1
were used without installation. Initially 248 GiB disk and approximately 45 GiB
available memory were reported; no full historical output scan was performed.
Fresh tested compiler SHA-256:
`a09eaaaafe622a79a7df04aa4cbf09de465c65756ecc6b1981c2b44ad03437d5`.

| Current-source probe | Fresh observation |
| --- | --- |
| Direct exact heap `sink<Counter>(move v,7)` | Seven stage dumps, check, native compile and execution pass; trace A, exit 42 |
| Lexical `relay<Counter>` to scalar/void sink | Same stages and execution pass; original owner reaches sink, trace A, exit 42 |
| Resource `relay<Resource>` to sink | Same stages and execution pass; original handle reaches sink, trace B, exit 42 |
| Explicit heap relay | All seven stage requests, check and native compilation reject at the retained-owner gate; no executable |
| Inferred heap relay and inferred sink | Same rejection and no executable |
| Two acyclic heap forwarding hops | Same rejection and no executable |
| Three positive memory companions | Unsuppressed Valgrind: zero errors, zero live bytes/blocks, zero suppressions |

These are **61** recorded command checks. Three existing Meson registrations
also passed freshly: gen-own-2a-contracts (nine independent mutation TAP tests),
gen-own-2a-no-llvm and gen-own-native-execution. The latter exercises existing
Resource/lexical result forwarding and recursion. These observations precede any
Q11C implementation and supply no Q11C PASS credit.

Probe inputs, exact commands/results and stage artifacts are external under
`runtime/native-current/gen-own-2b-design-baseline/`; checks.json and identity.json
record outcomes and hashes. The existing-test log is
`build/meson-logs/gen-own-2b-design-regressions.{txt,json}`. Initial preservation
identities are in `runtime/native-current/gen-own-2b-preflight.json`.

## Proposed bounded source contract

```astra
void sink<T>(owned T value, int code) where T: Ownable {}
void relay<T>(owned T value, int code) where T: Ownable {
	sink<T>(move value, code);
}
void outer<T>(owned T value, int code) where T: Ownable {
	relay<T>(move value, code);
}
```

Admit one named live exact native heap Class owner into one owned Ownable T
formal. Keep Q11B's synchronous caller, top-level native synchronous/nonthrowing
helper, concrete copied scalar neighbors and scalar/void result restrictions.
Use existing explicit/inferred T resolution and exact nominal identities.

A helper may retain its incoming owner or have **one structural forwarding site**
to a qualified generic owned-T callee. A conditional branch may execute that
site; another path retains responsibility until the helper's normal cleanup.
Existing ownership flow must prove no later use or second move. Borrow-only
inspection may finish before transfer; pending outer loans remain protected.
Multiple structural forwarding sites and ownership forwarding within loops are
outside this first proof, even where a more general path proof might be possible.

The owning transfer graph must be acyclic and end at a qualified retaining
consumer. There is no fixed hop-count restriction: a second hop follows the same
proof as the first. Structural unsupported transfers and cycles are checked
even in unreachable branches, so source order and dead code cannot bypass the
scope gate. Existing Resource and lexical forwarding/recursion keep their rules.

Heap generic owned results, generic owning locals, inline producers, multiple
owned T formals, aggregate T, subtype adaptation, persistent loans, generic
members/classes, foreign ownership consumers, async/throwing boundaries and
special allocator policies remain deferred. No result candidate, runtime domain
flag, generic dictionary/callback, refcount, object copy or new ABI is proposed.

## Source-grounded gaps and planned authorities

| Authority | Live source fact | Proposed change and required refusal |
| --- | --- | --- |
| [Semantic](../bootstrap/semantic/analyzer.vala) | heap_consumer_parameter accepts only a structurally retained incoming T; queued requests are checked after all bodies | Record exact generic transfer destinations while checking moves; qualify complete helper graph after all bodies. Reject unsupported target, cycle or more than one site without relying on declaration order |
| [Shared event proof](../bootstrap/semantic/generic-ownership-flow.vala) | One established ownership solver computes retained_owners from the entire event tree | Add a structural transfer summary beside retention, recording exact destination and owned formal ordinal; preserve the existing liveness solver. Raw move/release/acquire remains ineligible; loop transfers reject |
| [Inference transaction](../bootstrap/semantic/generic-call-inference.vala) | Argument fragments copy ownership events before committing call effects | Preserve transfer destination/ordinal when composing fragments; a cached inferred argument must neither lose nor duplicate a transfer |
| [Core](../bootstrap/core/verifier.vala) | Independently rebuilds owner events, validates acquisition/source/parameter contracts and retained-only heap scope | Rebuild transfer graph from verified Core calls and actual incoming owners, independently qualify symbolic requests and concrete heap instances; reject forged front-end eligibility or missing/misassigned acquisition |
| [Specializer](../bootstrap/core/generic-monomorphizer.vala) | call_target already derives inner heap ordinal from the mapped source owner's cleanup; contract maps incoming T to the exact heap cleanup | Reuse this path for each admitted transfer, verify nested scalar/void call forms preserve it. Do not select provenance from nominal T alone |
| [Canonical instances](../bootstrap/core/core-generics.vala) | Definition/type arguments plus heap-owned formal ordinal distinguish same-T lexical and heap uses | Keep this immutable key at every hop. Reject a mismatched concrete signature or call to a lexical instance from a heap actual |
| [CFG](../bootstrap/cfg/cfg-verifier.vala) | Exact capture/commit/acquisition checks and live-owner fixed point already govern concrete forwarding | Independently mutate moved-use, capture and acquisition in a forwarded program; reject and restore |
| [SSA](../bootstrap/ssa/ssa-verifier.vala) | Reconstructs object origins and verifies owned argument domain and cleanup against concrete pointers | Mutate forwarded heap origin/domain or duplicate cleanup; reject and restore |
| [Native correspondence](../bootstrap/nabi/native-validator.vala) | PTR with NativeObjectOriginPlan must agree with SSA exact Class and heap bit | Mutate a relay/sink origin plan; reject even if native physical verification alone passes |
| [LLVM destruction](../bootstrap/backend/llvm/llvm-classes.vala) | Existing complete Class destruction and heap free use the concrete cleanup contract | Reuse unchanged lowering; independently observe original pointer, deinit chain and one free, including no-deinit/empty and Q08 child cases |

Helper qualification is a least fixed point over finalized definitions: retaining
eligible sinks qualify first; a shaped forwarder qualifies only when its unique
destination and destination formal qualify. A cycle has no terminating proof
and cannot qualify. Repeat until no new helper qualifies, with no arbitrary
chain-depth limit. Semantic and Core each build their own graph using their own
stage identities; Core does not trust a Semantic eligibility field. Ordered
heap-request validation preserves deterministic first-invalid-site diagnostics.
Concrete Core must apply the same structural proof to reconstructed heap bodies.

## Conservation, origin and lifetime argument

1. Existing construction/move checks establish a named live exact owner. Concrete
   source cleanup records the original heap domain; aliases, borrowed formals,
   null construction and inline producers cannot manufacture this evidence.
2. Outer invocation captures that pointer, disarms its caller at the existing
   transfer boundary and acquires one incoming owner slot. Shared symbolic
   formals remain allocation-neutral. A concrete heap instance supplies the
   original domain through the existing canonical ordinal and heap cleanup.
3. At a qualified relay call, ordered argument evaluation reads/captures the
   incoming owner and checks loans. Capture changes ownership state to MOVED;
   physical commit clears that slot after argument effects and before invocation.
   The inner callee acquires the captured original pointer with the same exact
   cleanup and heap domain. There is no owner copy or owning intermediate local.
4. Same-T lexical and heap requests cannot share a canonical consumer/relay body.
   Each inner request derives its domain from the mapped source owner, not an
   allocation-neutral symbolic default. Independent concrete Core/CFG/SSA/native
   checks must agree with this identity at every hop.
5. The transfer graph's terminal sink retains its incoming responsibility and
   performs the existing complete destruction and one heap free on normal exit.
   Moved caller/relay slots contain null and do neither. A branch without a
   transfer leaves the owner live in the relay and uses its existing cleanup.
   Source joins and concrete CFG must agree; any indeterminate later use rejects.
6. Acyclic qualification composes the same argument across a second hop without
   new ABI channels or a chain-length exception. Fatal traps remain non-unwinding
   and are not normal-cleanup evidence. Heap owned-T results remain unproved.

This is a feasible design using inspected authorities, not execution proof for
Q11C. New mutation/native/optimization/memory controls are required after approval.
An irreducible need for allocator metadata or result semantics is a stop condition.

## Exact historical fixtures requiring separate consent

The following old rejection inputs become valid under the proposed scope:

| File | Exact case | Proposed still-invalid replacement |
| --- | --- | --- |
| tests/gen-own-2a/negative.py | forward | Forward to a generic owned-T result helper, which remains outside heap scope |
| same | inferred-forward | Infer the same unsupported owning-result destination |
| same | first-invalid-site | Two requests to an ineligible cyclic helper; retain exact first request location check |
| same | forward-after-loan | Completed loan followed by an unsupported owning-result destination |
| same | unreachable-forward | Unreachable transfer to an ineligible owning-result helper; structural gate must still reject |
| same | caller-before-consumer | Reversed declarations ending at an ineligible owning-result helper |
| tests/gen-borrow-1/negative.py | heap-consuming-wrapper | A heap wrapper forwarding recursively, which remains excluded |

Only these seven cases are proposed for replacement, retaining their names,
rejection checks and documented historical rationale. Their formerly rejected
behavior receives separate positive Q11C fixtures. The old Core forwarding
mutation actually inserts self-recursion, so it remains an invalid control and
needs no source replacement. Remaining historical expectations are preserved.

## Qualification after approval

Add a focused tests/gen-own-2b suite and external Meson recipe. Cover one/two-hop
forwarding, same-T lexical/heap in both call/declaration orders, explicit/inferred
forms, each copied scalar neighbor, completed loans, conditional retained versus
forwarded paths, scalar early returns, exact derived destruction, empty/no-deinit
and Q08 child-before-parent retirement. Instrument actual relay/sink entries for
original-pointer conservation; compare native, independent opt/llc O2 and a
separately compiled C entry. Count allocator/deallocator events separately from
normal-allocator unsuppressed Valgrind companions.

Reject source/IR cycles in declaration/module permutations, unqualified callees,
multiple sites, loop transfer, heap results/locals, nominal mismatch, overlapping
loans in both argument orders, second moves and invalid joins. Independently
mutate/restore Semantic/Checked admission evidence, Core forwarding acquisition
and canonical domain, CFG capture/liveness, SSA reconstructed origin/cleanup and
native correspondence. Execute a guarded duplicate-free control and an omitted
free memory control; do not execute an uncontrolled duplicate deallocation.

Fresh selected regression fences include Q11A, Q11B, GEN-OWN-1, Q08/Q10B and the
relevant parser/Core/CFG/SSA/native/Class/virtual-async/property registrations.
No full registry, LAZY Q4/CAD, real Linux/liburing, GUI/hardware, networking or
package installation is authorized. PASS requires final-source evidence and
normal task-only Git commit followed by the installed pm-next publisher.

## User decisions

The user approved the bounded Q11C scope and separately the seven enumerated
historical replacements. Qualification remains required before a milestone
result. ADR 0096 was available at review time; previous decisions retain their
historical scopes.
