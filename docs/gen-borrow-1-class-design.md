> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# GEN-BORROW-1: Class support and lifetime argument

**State: approved implementation scope.** On 2026-10-14 the
user requested Class support and its lifetime proof before implementation,
instead of approving the packet's Resource-only Q11A. After reviewing this
proposal, the user explicitly said, “Approve this Resource + Class borrowing
scope.” The accepted decision is `Q11A-RESOURCE-CLASS-BORROW`. This design alone
is not a qualification verdict. Q11 remains OPEN.

The inspected and tested baseline is `ac4492e7e783ddf16d784e78223555ab948807f6`
on `astra-lazy-1`. During that design phase, production compiler, language guides
and existing fixtures remained unchanged. The predecessor report's SHA-256 and all 21 supplied source
snapshot hashes match; its PASS remains historical finite Q10B evidence.

## Approved contract

Use one explicit `borrowed T` parameter in a top-level, synchronous native generic
function with `where T: Ownable`. Borrow-bearing signatures have only that loan
and copied boolean/integer/floating scalar arguments, and return void or a copied
scalar. They have no other borrowed/owned argument, owned result, receiver or
declared `throws`. Existing consuming generic functions remain governed by
GEN-OWN-1; an owned wrapper can call a borrow helper and later move its owner.
Callers must also be synchronous: borrowing in coroutine bodies, including
argument evaluation across await, remains outside this first slice.
Checked callers retain their existing behavior; this proposal introduces no new
generic borrow exception signature or suspension contract.

| Case | Proposed first implementation |
| --- | --- |
| Nominal Resource with exact declared cleanup | Borrow and forward; existing generic consuming wrappers remain legal |
| Exact native Class owner in lexical/caller-provided storage | Borrow and forward; an existing lexical `owned T` wrapper may borrow, then consume or return its incoming owner |
| Exact native Class owner allocated by `new`, including a heap factory result | Borrow through helpers that own nothing; caller retains heap destruction/deallocation, and may later use its existing concrete consuming/move/release paths |
| Heap Class entering a generic `owned T` parameter/result | Keep the current source rejection; allocation-provenance transport is a separate extension |
| Empty/no-deinit Class | Same lifetime rules; lack of a user destructor never grants copying or heap-leak permission |
| Exact derived Class specialization | Its existing object/header/address survives unchanged; generic calls do not adapt Derived to Base |
| Nullable live owner | Preserve null bits and OWNED state; no dereference is added by borrowing |
| Explicit null | Only existing contextual null behavior with explicit concrete type arguments; no new null inference or construction of symbolic T |

The first caller inputs are a live exact-typed concrete owning local/parameter,
an incoming live `owned T`, or an incoming `borrowed T` being forwarded. Ordinary
nonowning Class references, their stored aliases, owned child-field projections
and fresh inline owned producers are outside this first admission. A concrete
Class may contain already-supported owned fields: borrowing the whole Class
does not extract or acquire any field.

This makes generic borrowing stricter than concrete Class borrowing, which
already permits local reference copies. `borrowed T` cannot be copied into a
local even when a specialization happens to be a Class. The definition-time
contract is checked before specialization and cannot gain operations afterward.

`Ownable` still supplies no field, property, method or comparison capability.
Class specialization therefore enables bounded transport/forwarding, not
`value.some_class_member` in a generic body. Positive source programs must perform
observable scalar work and actual borrowed forwarding; an independent native
boundary observer must also verify the transported pointer. Generic member
access would require a separate capability design.

All original exclusions remain except the expressly proposed Class substitutions:
generic owning locals, records/arrays/slices as direct T, stored/returned loans,
closures, callbacks, async/await, generic members/classes, C/GObject boundaries,
runtime erasure/refcounts and new Class allocation/ownership policies.

## Why heap borrowing and heap consuming transport differ

[GEN-OWN-1](decisions/0060-generic-ownership.md) selects cleanup from nominal type
identity. In `CoreGenericMonomorphizer.concrete_contract`, symbolic Class cleanup
deliberately selects `!is_heap_object` or constructs `for_object`. Its instance
registry keys the generic definition and type arguments, without an allocation
domain. `SemanticAnalyzer.resolve_object_origins` tracks concrete Class signatures,
not symbolic T; `check_argument` rejects a heap owner against an unresolved
generic parameter's lexical allocation origin.

The fresh `heap-generic-consume` probe confirms that rejection at semantic,
Core, CFG, SSA, NABI, LLVM and executable compilation. This boundary must not be
removed merely to admit borrowing: doing so could select a destructor without
the required heap free, or attach lexical candidate storage to a heap result.

A borrow-only specialization has no Class owner acquisition, cleanup contract,
allocation or owned result candidate. Its existing native PTR channel passes the
same Class reference for lexical and heap callers. The caller's owner retains
the original cleanup and allocation provenance; the borrower has no authority
to select or change them. The same borrow-only specialization can therefore
serve both allocation domains without adding an instance-key dimension.

Full heap `owned T` wrapper support would require a new compile-time ownership
provenance design: allocation-domain obligations on consuming formals/results,
propagation through forwarding and recursion, compatible instance keys or another
proven domain-selection rule, and independent cleanup/result-storage checks.
Changing only a heap flag is insufficient. That extension is not implicitly
authorized by this proposal.

## Conditional lifetime proof

This is an argument for the proposed rules, not a claim that the absent generic
borrow implementation has been verified. The implementation must enforce each
premise and pass the independent controls below before a finite PASS is possible.
As with existing ownership proofs, foreign implementations must honor their
declared ownership/noescape contracts; this argument does not verify arbitrary
C side effects.

Represent an owner's proof facts as `(o, N, S, A, K, state)`: exact owner identity,
nominal type, referenced object/handle, allocation origin, cleanup responsibility
and ownership state. A loan records a dependent view of o for a call interval I;
it carries no K. For an incoming borrowed parameter, the root is the enclosing
call's loan, not a new owner. No runtime token or ownership metadata is needed.

The invariant is: throughout I, o remains usable and its referent S has not been
retired or replaced; N/A/K remain unchanged; the borrower has only bounded use.
Null is a valid live capability with no referent. MOVED is never equivalent to
null and cannot satisfy the invariant.

1. **Creation.** A named owning argument must be definitely OWNED, exact-typed
   and carry its established cleanup/storage authority. Capture a view of the
   same value without a move, owner acquisition or cleanup registration. Its
   caller storage is live for the enclosing invocation, or its heap storage
   remains live under the existing owning binding. Capturing an incoming loan
   requires the exact enclosing borrowed-noescape contract.
2. **Argument evaluation.** The loan stays pending from capture through all
   later argument evaluation and invocation. An earlier pending or completed
   consuming argument makes that owner unavailable for loan creation. A later
   move, consume, release or replacement of the same owner invalidates the loan
   and must reject before executable emission, including nested scalar-producing
   calls. Checking only owner state at capture is insufficient. A completed inner
   borrow returning an ordinary scalar ends its own loan; the scalar must not
   keep an artificial loan alive. Existing checked argument aborts abandon the
   outer invocation and its pending views before existing caller cleanup.
3. **Callee use.** Definition-time rules permit only direct bounded forwarding
   of T; they reject move, release, plain copy, address exposure, storage, owned
   return, member access, foreign transport and capture. The restricted signature
   gives the helper no second incoming owner that could alias its loan. Its
   scalar arguments cannot grant destruction authority for S. Any separately
   constructed concrete owner has independent storage under existing rules.
4. **Forwarding.** Passing the loan to another eligible synchronous helper
   creates a subinterval J within I with the same referent and no cleanup
   authority. By induction over nested calls, including each finite execution
   of bounded recursion, every frame retains the invariant. Divergence neither
   returns a loan nor permits the waiting caller to retire its owner.
5. **Control flow.** Every capture/use must be proved on each reachable branch;
   an OWNED|MOVED join cannot establish a live owner. The existing ownership
   fixed points check loop backedges. Repeated completed borrows preserve owner
   facts; repeated or conditional consumes retain their current rejection rules.
6. **End and eventual cleanup.** When the helper returns, its loan ends and no
   borrower value survives. The caller still has the same o/N/S/A/K and may use
   or lawfully transfer its owner afterward. Existing ownership analysis then
   selects exactly one normal retirement. Heap cleanup still includes free;
   lexical cleanup still ends the original storage lifetime. Fatal traps remain
   non-unwinding and do not acquire a new exactly-once-cleanup guarantee.

For this restricted source language, these premises exclude every source route
by which a generic borrower could shorten or extend its referent's lifetime.
Aliasing is not exclusivity: no readonly/noalias promise follows from the proof.
Ordinary concrete Class input/copy alias rules remain in the existing
[`OwnershipFlow.require_input_lifetime`](../bootstrap/cfg/ownership-flow.vala) authority.

## Source gaps and independent authorities

| Layer | Baseline evidence | Required implementation/control |
| --- | --- | --- |
| Semantic signature | `analyzer.vala:check_generic_position` rejects borrowed T; `collect_signature` excludes type parameters from borrowed admission | Admit only the approved Ownable loan shape; retain plain-T transport, owned-local, member and async guards |
| Source owner view | `check_expression` rejects reading a generic owner before it reaches `CheckedOwnedBorrowValue`; forwarded parameters already have noescape restrictions | Reuse that node and `CheckedParameterReferenceExpression`; require exact loan origin and bounded use, without creating an owner |
| Source call flow | `check_arguments`/`check_move`, `SemanticOwnershipFlow` and inference fragments sequence moves; pending field loans already exist | Add dependent owner-loan checking to this authority; check both orders, nested effects and temporary completion; do not create a second checker |
| Symbolic Core | `verify_parameter_contract` excludes borrowed type parameters; `verify_value` excludes symbolic owner borrows and plain Ownable values | Independently admit/restrict the loan signature and substituted boundary; rebuild owner reads/loan intervals; reject forged acquisition, release and escape |
| Specialization | Cloner preserves parameter contracts, owner identity and boundary links; consuming Class contracts are lexical | Preserve those links for borrowed T; exact Resource/Class type admission; keep heap owner consumption rejected; no cleanup for a borrowed parameter |
| Concrete CFG | `CfgOwnedBorrowInstruction`, `OwnershipFlow.read_value` and invocation reads require live owners; Class input/copy alias tracking is conservative | Reuse concrete Class/Resource rules after monomorphization; independently inject overlapping capture/transfer and wrong-boundary controls |
| SSA | Exact parameter contracts/types and cleanup identities are verified; Class noescape differs from handle forwarding rules | No symbolic T remains; wrong nominal Class/Resource and forged cleanup must reject; verify the stricter symbolic contract before materialization |
| Native/LLVM | Native plans intentionally erase lifetime metadata; `NativeAbiValidator.validate_call` compares SSA semantic identities before PTR mapping | Borrow has one ordinary PTR with no candidate or cleanup; independent nominal compatibility controls and native/O2 pointer/cleanup observations; no emitter workaround |

Native plan erasure does not itself prove lifetime safety. The semantic/IR
authorities prove it first, and the native compatibility bridge keeps distinct
semantic Class/Resource identities from becoming interchangeable PTR arguments.

## Fresh baseline evidence, 2026-10-14

The reusable build was revalidated to source `<historical-private-path>`,
output `<historical-private-path>`, debug, `werror=true`,
`linux_async=false`. A serial targeted Meson compile succeeded with ccache
disabled. The compiler SHA-256 is
`9a0106b7f9c1f21493784551a3c41eed4390693785c2faaffca0eed0133da4df`.

Five explicit registrations passed, with zero failures:

| Registration | Fresh observed result |
| --- | --- |
| `gen-own-semantic` | 5 TAP subtests; current ownership/type/scope boundaries |
| `obj-alloc-1-loan-contracts` | 5 TAP subtests; independent Core loan mutation/recovery checks |
| `param-borrow-negative` | 640 expected rejections across 52 cases, both concrete parameter spellings |
| `param-borrow-equivalence-execution` | 81 executions, 104 stage pairs, 234 deterministic comparisons, 39 machine pairs; concrete pointer identity control |
| `obj-alloc-1-native-execution` | 172 recorded checks; 7 native, 7 independent O2 and 7 unsuppressed Valgrind fixtures; fatal OOM and 26 negative forms |

The authored design probes add
45 checks: three actual native programs, their separately generated `opt`/`llc`
O2 programs, and three unsuppressed Valgrind runs with zero errors and zero live
bytes. Concrete helpers mutate the original owner's field, and generated helper
bodies contain no Class allocation, destructor/free or object-copy operation.

| Probe | Exact normal/native/O2 trace |
| --- | --- |
| Lexical concrete borrow/forward/reuse | `C41 B41 R42 D42` |
| Heap concrete borrow/forward/reuse/release | `C41 B41 R42 D42` |
| Concrete borrow followed by existing lexical generic consumption | `C41 B41 D42 R0` |

Here C marks construction, B borrower observation, R caller observation and D
destruction; each event is a separate output line. Fourteen further checks reject
heap generic consumption and the still-unimplemented borrowed-T signature at
six CLI stages plus native compilation; neither emits an executable.

The evidence and repeatable commands are described in the
probe README. These checks establish
current Class prerequisites and the heap-consuming blocker. They establish no
new generic borrow acceptance. No full-regression, historical LAZY campaign,
CAD, Linux async, hardware or GUI qualification was run. All 17 preexisting
untracked paths remain outside the authored design paths.

## Approved implementation acceptance

The finite feature must compile real Resource and Class `borrowed T` source,
forward its actual argument across generic helpers, perform observable work,
preserve owner reuse and subsequently clean once. Independently check borrower
entry addresses against original lexical, caller-result, heap, empty and exact
derived storage; retain cleanup/header identity and nullable-owner behavior.
Generic owned wrappers must pass for lexical Class and continue to reject heap
Class at source unless a separate provenance design is approved.

Negative controls must cover absent Ownable, wrong same-layout nominal identity,
subtype adaptation, invalid signature/result, explicit/inferred calls, unsupported
actuals, stored/returned/copied/moved/released loans, both argument orders, nested
consumption, consumed owners, branch joins and loop backedges. Forwarded symbolic
loans must not become ordinary Class aliases during definition verification.

Mutation controls must separately forge borrowed-as-owner acquisition/cleanup,
wrong substituted boundary, owner invalidation during a pending loan, wrong
nominal argument and heap-as-lexical cleanup. Positive native/O2 programs need
independent observer/memory checks, with safely isolated omitted- and
double-cleanup fault controls. Run a bounded explicit generic/ownership/Class,
Q10B and affected error/async fence; record every actual result and limitation.

Only after those gates may the capability guide describe the approved finite
subset. This design is not a PASS and does not replace the current report ZIP.
The user approved this mixed Resource/Class borrow scope and deferred the
heap-consuming generic provenance extension. Current engineering evidence is
recorded separately in the finite validation note.
