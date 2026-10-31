# GEN-OWN-2A: finite heap Class consumer design

State: **Q11B approved before implementation**, 2026-10-14. The user explicitly
answered “I approve” after reviewing this finite design. Inspected baseline:
`cfcca9bf2e9f8fefa057e727cf8596cc6a99e0f3`, tree
`611a381c40a12f170e923f4e44c4bdde53d5f568`. The previous Q11A decision
authorizes borrowing, not heap ownership consumption. This is a design argument
and a qualification plan, not a claim that the proposed semantics already pass.

## Proposed source contract

```astra
class Counter {
	int id;
	init(int id) { this.id = id; }
	deinit() { /* existing concrete destructor work */ }
}
void consume<T>(owned T value) where T: Ownable {}
int main() {
	owned Counter lexical = Counter.init(10);
	var heap = new Counter(20);
	consume<Counter>(move lexical);
	consume<Counter>(move heap);
	return 42;
}
```

The new admission is one explicit move of a live, exact native heap Class owner
into one `owned T` parameter of a top-level, synchronous, nonthrowing native
generic consumer. Other parameters and the result are copied bool/integer/f32/
f64 values, or a void result. Use synchronous callers for this finite scope.
Retain current inference; no new grammar, member capability or null inference.

The consumer retires its incoming owner on normal exit, including supported
early returns and branches. It can invoke the already accepted borrow-only T
helpers. It cannot move or forward that incoming owner onward, return an owned
T, manufacture an owned T local, or recurse while carrying its ownership.
These restrictions apply to **heap instantiation**, preserving existing legal
Resource and lexical Class forwarding/recursion. Empty/no-deinit and exact
derived Classes remain subject to their existing concrete cleanup contracts.
Generic Derived-to-Base adaptation remains excluded.

## Fresh baseline and preserved work

The external Meson build's source routing was checked against the real repository;
its strict compiler target build returned 0 with ccache disabled and serial
compilation. Tested compiler SHA-256:
`374104165721e5cf50a6ef2629c07031f4fa98c7d99494fc61a1ca4c131dcdde`.

| Current-source probe | Actual result |
| --- | --- |
| Lexical `consume<C>(move c)` | Seven stage dumps, native compile and execution pass; executable returns 42 |
| Heap `borrow<C>(c,42)` | Seven stage dumps, native compile and execution pass; executable returns 42 |
| Heap `consume<C>(move c)` | Seven stage requests and executable compilation reject with the resolved heap/lexical origin diagnostic; no executable or stdout |
| Heap borrow memory | Unsuppressed Valgrind returns 42 with zero errors, zero live bytes/blocks and zero suppressions |

These are **27** recorded baseline checks. Three additional existing Meson
registrations passed: `gen-own-native-execution`, `gen-borrow-1-contracts`
(9 TAP subtests), and `gen-borrow-1-native-execution`. The first exercises current
Resource/lexical owning programs; the latter retains its nine Resource/Class
native/O2/C-client programs and memory controls. They qualify the baseline only.

Probe inputs, commands and outcomes are in the external current runtime's
`gen-own-2a-design-baseline/{checks,identity}.json`; the Meson log is
`build/meson-logs/gen-own-2a-design-regressions.{txt,json}`. The predecessor
report's SHA and five supplied source hashes matched live files. All 17 initial
untracked names were inspected with bytes/modes and remain untouched. Index and
tracked state were clean. Archive and sibling HEAD/branch retain their prior
identities. The completed Q11A runtime was preserved by directory rename to
`runtime/native-completed-ASTRA-GEN-BORROW-1-NATIVE-1-cfcca9bf` when intake refused
its task evidence files; nothing was deleted. Historical ignored outputs were
not traversed or cleaned.

## Source-backed gap matrix

| Authority | Current fact | Required finite change and independent check |
| --- | --- | --- |
| [Semantic source](../bootstrap/semantic/analyzer.vala), `check_heap_local`, `check_move`, `check_argument` | Concrete owners retain heap origin; symbolic owned formals default lexical and reject a heap actual | Admit only a complete named exact heap move to an eligible consumer; preserve ownership sequencing and live-owner proof |
| [Checked/Core construction](../bootstrap/core/builder.vala), `ownership_contract` and owned arguments | Existing concrete Class cleanup distinguishes heap/lexical; argument construction selects the shared formal's origin | Preserve each admitted actual's origin without changing the shared symbolic formal for other calls |
| [Instance identity](../bootstrap/core/core-generics.vala), `GenericFunctionInstance` | Canonical key contains definition and type arguments only | Add compile-time consuming-parameter storage domain to canonical matching; independently verify signature/owner correspondence |
| [Specialization](../bootstrap/core/generic-monomorphizer.vala), `request`, `concrete_contract`, `CoreInstanceCloner` | Symbolic Class cleanup always selects nonheap; parameters copy the origin's heap bit | Select existing exact heap cleanup for the admitted heap instance and preserve its incoming owner/argument boundary |
| [Core verifier](../bootstrap/core/verifier.vala), `verify_call`, parameter acquisition | Actual cleanup, parameter origin and exact source owner must agree | Independently validate the finite symbolic heap request and concrete instance domain; do not trust front-end eligibility metadata |
| [CFG](../bootstrap/cfg/cfg-verifier.vala), acquisition/capture and ownership flow | Concrete parameter and cleanup heap bits must agree; moved state has a fixed-point authority | Reuse unchanged checks where sufficient; wrong-domain, moved-use and overlapping-loan mutation controls |
| [SSA](../bootstrap/ssa/ssa-verifier.vala), reconstructed object origins | Cleanup must match independently reconstructed heap/lexical pointer domain | Forge incorrect cleanup and require rejection, then restore/reverify |
| [Native ABI](../bootstrap/nabi/native-builder.vala), [correspondence](../bootstrap/nabi/native-validator.vala) | Existing owned Class PTR channel has `NativeObjectOriginPlan`; heap bit/type must match SSA | Retain that existing channel; independent wrong heap-origin/type/channel controls |
| [LLVM Class destruction](../bootstrap/backend/llvm/llvm-classes.vala), `destroy` | Established heap path calls complete Class destruction, then allocator deallocation; absent user deinit still reaches free | Reuse it; actual pointer/deinit/free observations, native/O2 execution and unsuppressed memory checks |

## Alternatives and recommended representation

1. **Compile-time provenance-sensitive instances (recommended).** Keep the
   shared generic definition allocation-neutral. A consuming request includes
   the exact type arguments and the admitted owning parameter's heap/lexical
   domain. One owned T plus scalar neighbors makes this a bounded key: the heap
   parameter ordinal, or no heap parameter. Immutable canonical key data must
   participate in matching and verification. Existing instance ordinals already
   produce distinct emitted symbols. Borrow-only instances need no domain key,
   because they acquire no cleanup.
2. **One body and the existing Class pointer channel alone.** The PTR channel
   preserves identity but does not tell a generic body whether to free storage.
   The same T can be lexical or heap. Choosing one cleanup would either leak a
   heap object or free lexical/caller storage. It cannot meet this task's same-T
   witness without another proven discriminator.
3. **Runtime flag/dictionary/destructor adapter.** A new per-object heap flag,
   generic cleanup callback or ownership dictionary could discriminate domains,
   but changes representation/ABI and exceeds this submission. It is unnecessary
   for direct finite consumption when the caller already has a compile-time
   concrete ownership origin.

The recommended design adds compiler-only instance information, not an object
header, refcount, generic runtime witness or hidden copy. Existing Class runtime
destructor machinery is reused; no new generic destructor callback is introduced.

## Ownership and lifetime argument

1. **Establish origin.** Existing construction/move authorities identify a live
   owning Class binding, its exact nominal type and heap cleanup. An alias,
   inline producer or unproved/maybe-moved binding cannot create a heap request.
   Explicit null carries no named owner and cannot manufacture a heap instance;
   existing Resource/lexical null behavior is not redesigned.
2. **Capture and commit.** Keep left-to-right argument evaluation and existing
   owner capture/commit rules. Q11A dependent views must remain live through their
   containing invocation. A nested consumption while an outer loan is pending
   rejects in either argument order. A completed scalar-producing loan can end
   before the later legal move. The caller loses responsibility only at the
   existing lawful transfer boundary.
3. **Choose an instance.** Same-definition/same-T lexical and heap requests
   select distinct canonical instances regardless of discovery order. A heap
   request cannot match the lexical instance. A borrowed helper called from
   either consumer still acquires no owner and can share its borrow-only body.
4. **Acquire the original pointer.** Clone the incoming owned parameter with
   heap origin and map its symbolic cleanup to the existing exact Class heap
   contract. No callee result candidate exists for scalar/void results. Core
   acquisition, CFG capture and SSA/native correspondence must all agree on
   type, pointer and domain; caller storage cannot be substituted.
5. **Retire once.** The eligible body retains responsibility until its normal
   cleanup edge. Existing owner state and cleanup ordering handle return paths.
   Heap cleanup invokes the established complete derived/base destructor chain
   and then frees that allocation; no-deinit/empty Classes still free. Lexical
   instances run their existing destructor-only cleanup. Fatal traps remain
   non-unwinding, with no new unwinder or exception policy.
6. **Fail closed on forwarding.** Determine consumer eligibility from the
   finalized checked body and rebuild it independently from symbolic Core.
   Retain the existing structured ownership proof; inspect its incoming-owner
   events to exclude onward moves/releases/acquisitions and ownership-carrying
   recursion, including unreachable unsupported forms. Queue/validate heap
   requests after bodies are checked so declaration order cannot bypass this
   guard. Shape/body eligibility is a scope gate, not a second liveness checker.
   Independently authored Core must also fail a heap request to an ineligible
   body. Existing lexical forwarding remains available through lexical keys.

The argument supports a feasible implementation using established channels.
Independent mutation and actual native memory gates remain required before a
PASS. A need for runtime allocation metadata or unproved forwarding would be a
stop condition requiring a different user decision.

## Qualification required after approval

Add a focused `tests/gen-own-2a/` suite and a portable external Meson recipe.
Execute same-T lexical/heap cases in both orders, explicit/inferred moves,
concrete heap-owner moves, completed/overlapping loans, copied scalar/early-return
consumers, empty/no-deinit and exact derived Classes. An independently compiled
C observer must check the actual original receiver and distinct deinit/free
obligations; reuse the established allocation observation approach where useful.
Separate native and opt/llc O2 runs must agree. Unsuppressed memory positives and
isolated omitted-free/premature-or-double-free fault controls must detect failures.

Source negatives cover heap result/forwarding/recursion, generic owner locals,
multiple owners, inline producers, wrong nominal/upcast, aliases, missing
Ownable, invalid histories, capture/storage and async/throwing/foreign boundaries.
Forge incorrect instance domains, cleanup/acquisition and SSA/native origin
contracts; reject at the independent authority and restore/reverify. Run Q11A's
focused/regression selection and relevant Q08/Q10B/OBJ-ALLOC/OBJ-FIELD fences.
Do not change unrelated historical expectations without separate user consent.

Q11 stays OPEN. Heap generic results, broad forwarding, generic owner locals,
aggregate owners and general lifetime policies remain deferred. No full registry,
CAD/LAZY Q4, real Linux/liburing, GUI/hardware or package/network work is covered.
