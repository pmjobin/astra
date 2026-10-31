# GEN-OWN-2C: direct incoming heap Class result design

State: **Q11D approved before semantic edits**. The user explicitly answered
“Approve bounded Q11D & Approve these two replacements”. The reviewed design
SHA-256 was `a3ae5799dfba9e53037486d910947b963d3f487b8fdb3e08a20b80c48f5e2dab`.
ASTRA-GEN-OWN-2C-HEAP-RESULT-1 does not inherit approval from Q11A/B/C.
Q11 remains OPEN. This document records the current-source baseline and the
lifetime/physical-result argument presented for review.

## Verified starting point

The installed pm-next intake selected the sole matching submission, SHA-256
`cce1786aa76062d5659d611faf0dc64cdb41fda4022bc6f64e6b2032092c6a72`.
Live branch astra-lazy-1, HEAD
`43bd32005f49da3240bd3a2115771da7571e71f0`, tree
`af8b19ddf1a6879f127ee84f75eec68eeebbfa3c` match the packet. Tracked files and
the index were clean. All nine supplied source hashes match live files.
The 17 initial untracked user files were inventoried by path, mode, size and
SHA-256; none is a task edit target. Ignored build output was inventoried at its
directory boundary, without traversing or changing it. Archive tip and worktree
routing were recorded. Existing hooks remain enabled.

Intake refused unknown evidence in the published Q11C runtime. The complete
directory was preserved by rename to
`runtime/native-completed-ASTRA-GEN-OWN-2B-HEAP-FORWARD-1-43bd3200`, then the
new packet was prepared. No historical evidence was deleted. The canonical
previous report remains unchanged at this design stage.

The reusable external Meson build resolves to this real repository, with debug,
werror=true, b_pch=false and linux_async=false. All 217 Ninja commands for astrac
were freshly replayed serially with CCACHE_DISABLE=1, using the existing Meson
recipe and output paths. Compiler SHA-256 is
`0841a95dc63a5a2ac6b7fe4c6969fe87d797e1694235d72e51a763f2c39e30f1`.
Toolchain: Vala 0.56.19, GCC 16.2.1, LLVM 22.1.8, Meson 1.11.2, Ninja 1.13.2,
GLib/GObject 2.88.4, Valgrind 3.27.1. No installation occurred.

Fresh baseline evidence contains **103 command checks**, six positive programs,
four negative programs, and six standard-allocator unsuppressed Valgrind runs
with zero errors, zero live bytes/blocks and zero suppressions.

| Current-source witness | Observed result |
| --- | --- |
| Explicit/inferred direct generic heap consumers | Pass; trace AB |
| Explicit/inferred two-hop generic heap consumers | Pass; trace CD |
| Explicit owned / inferred var lexical generic results | Pass; trace EF; Class result candidate remains |
| Explicit owned / inferred var Resource generic results | Pass; trace GH; no Class candidate |
| Concrete incoming heap Class return into var / owned local | Pass; trace IJ; original incoming PTR returned |
| Existing Resource and lexical Class recursive results | Pass; trace AB |
| Generic incoming heap Class result: explicit/inferred calls, var/owned destinations | All four reject at the heap-generic scope gate in seven dumps, check and native compilation; no executable |

Commands, source/compiler/artifact hashes, diagnostics and memory logs are in
`runtime/native-current/gen-own-2c-design-baseline/`. The first baseline attempt
mistakenly asserted a nonexistent NABI dump label; its receipts were preserved,
the harness corrected to inspect actual PTR signatures, and all probes rerun.
The dump does not expose NativeObjectOriginPlan metadata; its presence is
established by inspected builder/validator source, not inferred from that label.
Build and preservation receipts are in the matching external runtime.
Five existing Meson registrations also passed freshly: gen-own-native-execution,
gen-own-2a-contracts (nine TAP controls), gen-own-2b-contracts (17 TAP controls),
and their two no-LLVM linkage checks. This is a preimplementation comparison
fence, not qualification of Q11D. Its logs are gen-own-2c-design-regressions in
the external runtime and Meson log directory.

## Proposed finite source contract

```astra
owned T echo<T>(owned T value) where T: Ownable {
	return move value;
}
void retire<T>(owned T value) where T: Ownable {}
int main() {
	var original = new Counter();
	var received = echo<Counter>(move original);
	retire<Counter>(move received);
	return 0;
}
```

Allow exactly one owned Ownable T formal, copied concrete scalar neighbors, and
an owned result of that same exact T. Helpers and callers are synchronous;
helpers are top-level native and nonthrowing. For a heap Class application, the
body has exactly one structural direct return of the incoming owner, outside
loops, with every reachable normal exit transferring it. Completed Q11A borrows
and copied scalar computation do not change responsibility. Unsupported moves,
producer forwarding, recursion, second result sites and loop result sites reject
structurally, including dead code. Existing definition-time path analysis still
proves liveness and normal-path return completeness.

An actual is a named live exact native heap Class owner. Its result is acquired
directly into a fresh named concrete owning Class local, using existing var or
explicit owned Class grammar. Exact derived identities remain exact; no upcast.
The receiving owner can be used, borrowed, released or moved to an approved
Q11B/C consumer under existing rules. Resource and caller-backed result paths,
including their existing generic recursion, retain their current authority.

Generic owner locals, nested/inline consuming producers, heap result forwarding,
fresh construction in generic source, multiple owners/results, ambiguous origin
joins, borrowed/plain acquisition, async/throws, foreign adapters, generic
members/classes, aggregates and new allocator policy remain excluded.

## Lifetime argument and existing physical representation

| Point | Sole cleanup responsibility | Pointer/storage fact |
| --- | --- | --- |
| Construction | Original concrete caller local | One native heap allocation P |
| Argument capture/commit | Incoming generic formal after commit | Capture P once; former caller disarmed |
| Direct return capture | Escaping owned result | Capture current P before cleanup; formal disarmed |
| Caller acquisition | Fresh concrete result local | Acquire P with exact heap Class cleanup; no candidate |
| Lawful retirement | Receiving local or approved later consumer | Complete Class deinit chain and exactly one free(P) |

At no completed transfer do two live slots own P. Captures preserve the source
until its existing commit; failed argument/consumer checking cannot invent an
acquired result. Return capture precedes cleanup and clears the current formal
pointer. Its subsequent cleanup sees null. The result receiver is the next owner,
not an object-byte copy. An unacquired result must reject. Fatal traps are
nonunwinding and provide no normal-exit cleanup guarantee.

The fresh concrete comparator's SSA has ACQUIRE(P), RETURN(P), cleanup(null),
END(null), then `ownership-return P`. Its LLVM function is
`define internal fastcc ptr @astra.fn.0(ptr %p0)` and returns `%p0` unchanged.
There is no candidate parameter, allocation or object copy in that helper.
Unoptimized LLVM contains null-guarded unreachable cleanup blocks; this does
not mean the returned owner is destroyed. Allocations belong to its caller.
The lexical generic comparator instead has
`(candidate PTR, owner PTR) -> PTR` and retains caller-backed storage.

The immutable key already consists of CoreGenericIdentity, ordered concrete
types and heap_owned_parameter. With one exact T formal returned directly, the
result domain is determined by that formal: heap ordinal => heap result;
ordinal -1 => existing Resource/lexical result. No additional key is required.
Shared symbolic definitions remain allocation-neutral. Both actual request
orders must produce distinct same-T heap/lexical bodies and result plans.

## Source-grounded gaps and bounded planned changes

| Authority | Current fact and required change |
| --- | --- |
| [Semantic analyzer](../bootstrap/semantic/analyzer.vala) | Lines 1136–1148 exclude every owned result from heap eligibility. Lines 2097–2105 and 2420–2427 derive a local's origin from FunctionSymbol.heap_result, which is neutral for generic definitions. Derive provisional result domain from each verified exact named actual and matching T formal; validate structural result eligibility after all bodies. Integrate the same per-call origin with the concrete origin prepass. Never stamp a generic definition heap by nominal Class alone. |
| [Ownership flow](../bootstrap/semantic/generic-ownership-flow.vala) / [inference](../bootstrap/semantic/generic-call-inference.vala) | Existing MOVE/RETURN events prove liveness; the Q11C structural summary accepts only retaining/forwarding consumers. Annotate direct returned-owner moves in this existing event proof, preserve that annotation through inference fragments, and distinguish a one-return terminal from a consuming terminal. Keep Q11C graph qualification separate from result qualification; do not enable result forwarding. |
| [Core verifier](../bootstrap/core/verifier.vala) | Reconstruct the direct return and exact formal/result cleanup independently from Core, for symbolic requests and concrete heap instances. For a symbolic generic Class call, derive result domain from the verified actual/source cleanup before checking candidate exclusivity and exact acquisition. Reject forged Checked eligibility, wrong source/formal/type, wrong domain, extra return, candidate alias and missing acquisition. No trusted upstream result bit. |
| [Instance registry](../bootstrap/core/core-generics.vala) | Existing canonical key verifies incoming storage domains. Also verify its concrete result domain/cleanup/candidate agreement where an owned Class result derives from the selected heap formal. Preserve Resource/lexical keys. |
| [Specializer](../bootstrap/core/generic-monomorphizer.vala) | Lines 230–234 currently select lexical result cleanup and storage. Derive concrete heap result from the already proved key/formal, use existing heap cleanup, and omit CoreResultObjectStorage. Line 502 currently selects OWNED_PARAMETER_STORAGE for every returned Class parameter; select HEAP_OBJECT from the mapped exact owner cleanup for the admitted heap result. |
| [CFG](../bootstrap/cfg/cfg-verifier.vala) / [flow](../bootstrap/cfg/ownership-flow.vala) | Existing associated unique return capture, exact origin, source liveness and move-and-clear checks represent this contract. Prove independently with missing/reordered capture, moved read, escaped-owner cleanup and caller double acquisition mutations. |
| [SSA](../bootstrap/ssa/ssa-exceptions.vala) / [verifier](../bootstrap/ssa/ssa-verifier.vala) | Heap RETURN events already require the exact captured terminator pointer; reconstructed origin and owner-state flow check domain/disposition. Exact current-pointer flow currently applies only to record Resource owners. Exercise coordinated wrong-pointer and cleanup mutations; if needed extend that existing pointer proof to native heap Class owners, and check returned incoming pointer identity using existing source_parameter. No new lifetime solver or generic runtime authority. |
| [NABI](../bootstrap/nabi/native-builder.vala) / [validator](../bootstrap/nabi/native-validator.vala) | Existing heap_result plan is NativeObjectOriginPlan(exact Class, heap=true), PTR result with no NativeOwnedObjectResultPlan. Independent SSA correspondence checks both heap bit and Class identity. Mutate wrong candidate/origin and restore. Physical widths alone are insufficient. |

The established LLVM destruction and concrete native PTR profile are reusable;
no production backend/public ABI, allocator tag, dictionary, callback, refcount,
hidden heap copy or new syntax is proposed. Any need for a new key/profile,
uncertain provenance or pervasive representation changes is a stop for further
design review. This is a feasible source-grounded design, not Q11D execution
qualification; mandatory mutate/reject/restore and native/memory tests remain.

## Two historical cases requiring separate consent

Only these current rejection inputs become valid under this direct-result scope:

| File and exact case | Proposed still-invalid replacement |
| --- | --- |
| tests/gen-own-2a/negative.py: owned-result | Add a copied bool neighbor and two mutually exclusive direct `return move v` sites; preserve named heap result acquisition and the scope diagnostic prefix |
| tests/gen-own-2b/negative.py: heap-result-direct | Put its one direct return inside `while(true)`; preserve named heap result acquisition and the scope diagnostic prefix |

Both retain exit 1, deterministic useful diagnostic, no stdout/internal error,
and no executable checks. Their original direct-return behavior receives new
positive controls. Q11B/C result-chain, dead second-site and cycle cases remain
invalid and need no expectation edits. Other historical expectations and ADRs
remain untouched. These two fixture changes require separate explicit consent.

Concrete proposed helper bodies are
`owned T relay<T>(owned T v,bool b) where T:Ownable { if(b){return move v;} return move v; }`
and
`owned T relay<T>(owned T v) where T:Ownable { while(true){return move v;} }`.
Both are called with a named heap C source and a var result destination. An
additional 18 preimplementation diagnostic/no-executable checks passed for
these proposals; receipts are proposed-fixture-checks.json beside the baseline.

## Review alternatives and qualification boundary

1. Approve bounded Q11D above, then implement and qualify it.
2. Hold semantic implementation for a deeper concrete heap-return ABI study.
3. Hold for further design review.

After approval, add tests/gen-own-2c and the next available ADR, 0097. Prove
same-T domains in both request/declaration orders; explicit/inferred named
acquisition; original pointer at entry/return/receiver; exact derived, empty,
no-deinit and Q08 child cleanup; normal native, independent opt/llc O2 and C
client/entry witnesses. Separate allocation/free observers from standard
allocator Valgrind; detect omitted free and stop duplicate free before the
second real deallocation. Run independent Core/CFG/SSA/native controls and the
selected established Q11A/B/C, owned-result/recursion, Class, Q08/Q10B, virtual
async and property fences. Record actual commands, traces and hashes.

Full historical registry, LAZY Q4, CAD, live Linux/liburing, GUI/hardware and
broader Q11 composition are NOT_RUN. Approval and passing finite tests would
not close Q11 or requalify those historical milestones.
