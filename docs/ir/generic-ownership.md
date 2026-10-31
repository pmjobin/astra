# Generic ownership in Checked and Core

GEN-OWN-1 represents generic ownership only in semantics and parameterized Core.
It reuses the existing exact capability namespace, ownership operations, generic
instance registry and concrete cleanup/ABI paths. No OwnedType constructor is
introduced: ownership remains a contract over the same underlying type token.

## Authority and Checked model

`GenericCapabilityIdentity.OWNABLE` extends the stage-neutral capability enum.
`GenericCapabilityNamespace` interns the existing GenericCapabilitySymbol shape
for Ownable. Requirements and forwarding retain exact identity membership,
ordered source requirements and provenance. `GenericCapabilityAuthority` is the
only concrete satisfaction matrix; contract selection is not a second matrix.

`TypeParameterType.transport_mode` is OWNABLE exactly when its immutable explicit
capability set contains Ownable; otherwise it is PLAIN_COPY. TypeParameterSymbol
and CoreTypeParameter expose this authority. The legacy capability accessor
returns GEN1_PLAIN_COPY only for PLAIN_COPY; an Ownable parameter returns OWNABLE.
`GenericArgumentTypes.plain_copy` rejects Ownable parameters as well as concrete
owners. Its `accepts` operation selects the exact parameter transport domain.
Old unconstrained and value-capability parameter dump forms remain unchanged.

An owned parameter retains PointerParameterContract.OWNED_TRANSFER and an exact
TypeParameterType. Its incoming LocalSymbol is recognized as a generic owner
through its exact incoming parameter and OWNABLE mode. It has no Resource cleanup,
Class symbol, destructor or lexical ObjectStorage. It represents incoming
responsibility, not a new source local declaration.

Owned results retain ResultOwnershipContract.OWNED_TRANSFER over that same T.
CheckedOwnershipMove retains the exact source LocalSymbol, T and source span;
CheckedOwnedArgument retains the exact target parameter and substituted argument
type. CheckedOwnershipReturn retains either the incoming move or a direct generic
owned-result producer. Source construction and null T are rejected; local
ownership uses the separate bounded GEN-OWN-2D contract below.
Concrete generic-call results resolve their concrete acquisition
metadata without checking a specialized source body.

## Definition-time proof and independent Core verification

The existing OwnershipState finite possibility set now lives in a stage-neutral
semantic authority. Its OWNED, MOVED, RELEASED values and dump names are unchanged.
GEN-OWN-1 uses OWNED/MOVED for generic parameters; generic release/rearm is absent.
Nullable incoming owners still enter OWNED rather than a runtime null-active state.

`GenericOwnershipFlow` temporarily records a structured proof during checking.
Its exact owner keys, move source spans and sequence/choice/loop/jump events have
no CFG nodes, ABI plan, destructor or storage layout. Semantic checking emits
moves in source evaluation order. Choice events capture conditional and
short-circuit effects. Loop evaluation joins the entry and backedge possibility
sets to a fixed point; break, continue and terminating returns retain their
structured destinations. Unreachable exits do not contribute ownership facts.
Break and continue exits retain exact stage-owned loop targets, including an
enclosing target in independently authored Core; the proof never re-resolves a
target from nesting.
A move requires definitely OWNED. Joins that may be MOVED reject another move.
Owned generic results also require transfer on every normal return path.

CoreVerifier independently reconstructs this proof while verifying exact Core
contracts and operations. It does not consume a Checked proof or trust an
upstream success bit. It rejects forged double moves, copies, local owner
construction, generic null, wrong contracts, missing requirements and illegal
result provenance before the monomorphizer can create an instance. This is
verification of a stage-owned graph, not source rechecking or SemanticAnalyzer
re-entry. The temporary proof is destroyed after each verification.

## Parameterized Core contracts

`CoreCleanupContract.for_parameter` generalizes compile-time responsibility with
an exact TypeParameterType. It has no external symbol, object class or destructor.
These contracts are canonical per exact parameter token. CoreBuilder appends them
after existing concrete cleanup descriptors in the program inventory. Their dump is
`(ownership-contract #n : T (requires Ownable))`.

CoreOwnedLocal represents the incoming parameter's slot and retains its root
scope and CoreParameter. GEN-OWN-2D's distinct local has no CoreParameter and
acquires through CoreOwnershipTransfer with that same cleanup.
CoreAcquireParameter, CoreOwnedArgumentValue and
CoreOwnershipReturn reuse existing ownership operations with that parameterized
contract. Owned argument values retain their substituted type separately from
the target's formal parameter type. A move remains an explicit source-owner
reference in the owned argument/return; it never becomes an ordinary CoreLoadValue.

A generic owned result has no CoreResultObjectStorage. Returning an incoming
owner retains its incoming-parameter provenance through the source owner. Direct
forwarding retains the exact CoreGenericCall and target requirements. Neither
operation invents an intermediate owner slot. GEN-OWN-2D separately authorizes
one exact incoming-to-local transfer below. Other generic local acquisitions
and ordinary loads of an Ownable T remain rejected.

## Existing monomorphizer and concrete domains

CoreGenericMonomorphizer validates the generic graph first, then verifies the
ordered actual type arguments against exact transport/capability requirements
before registering a function instance. GEN-OWN-1's key is CoreGenericIdentity
plus ordered concrete semantic type identities. GEN-OWN-2A additionally keys
the finite heap consuming formal's ordinal, as described below. ABI and layout
remain outside that key. Recursive signatures register
before FIFO body cloning, so direct and mutual calls reuse canonical instances.

The existing CoreInstanceCloner substitutes owner slots, arguments and result
contracts while cloning other operations. `concrete_contract` selects the exact
program CoreHandle cleanup for a Resource, or the canonical CoreClass cleanup
contract for a Class. No-deinit and empty classes still receive their existing
lifetime-only responsibility. Concrete class descriptors and destructor targets
are reused; the operation does not infer a destructor from spelling.

| Parameterized operation | Resource specialization | Class specialization |
| --- | --- | --- |
| Owned incoming parameter | Existing CoreOwnedLocal and Resource cleanup | Existing CoreOwnedLocal and exact class cleanup |
| Move argument | Same handle pointer and source slot | Same original storage owner pointer |
| Drop at exit | Existing release, skipping null | Existing deinit/lifetime end, skipping null |
| Return incoming owner | Existing pointer transfer | OWNED_PARAMETER_STORAGE provenance; no relocation |
| Direct result forwarding | Existing producer capture with exact Resource consumer | FORWARDED_OWNED_RESULT with caller result-candidate threading |

Direct Resource result producers use the existing return-producer representation
already used by objects. Core, CFG and SSA verifiers accept its one immediate
consumer and exact cleanup/type identity. There is no new Resource ownership
operation or source-level generalization of ordinary Resource return syntax.
The CFG/SSA builders already capture that producer before normal cleanup.

Caller-backed Class specialization creates CoreResultObjectStorage only once
the return type is concretely ClassType. The cloner threads it into direct result forwarding and
sets concrete object provenance. Returned parameter storage remains outside the
current frame. The incoming pointer is returned unchanged; the candidate may be
unused. Resource specialization never receives this storage plan.

Parameterized responsibility descriptors are filtered out of the returned Core
program; existing concrete descriptors keep their identities and relative order.
Their ordinals are normalized after filtering; compiler-produced Core already
places generic contracts last, preserving all old concrete dump ordinals. Newly
needed Class contracts are appended in deterministic request order. Concrete
verification runs before returning the specialized graph. No generic ownership
contract, TypeParameterType or generic call remains.

## GEN-OWN-2A/2B consuming and forwarding allocation domains

The finite direct heap Class consumer keeps symbolic owned T formals
allocation-neutral. Checked arguments derive concrete heap responsibility from
their named source owner. Source eligibility is finalized after every body;
Core independently rebuilds incoming-owner events. GEN-OWN-2B qualifies one
structural forwarding site to a compatible generic callee, using finalized
graphs with retaining sinks as terminals. A least fixed point propagates
qualification along exact destination/formal edges; cycles cannot qualify.
Multiple sites, loop transfers, result forwarding and excluded signatures reject,
including unreachable events. Existing path-state analysis remains unchanged.

`GenericFunctionInstance` adds an immutable heap consuming-parameter ordinal to
definition/type matching. Canonical consuming ordinals also verify the concrete
signature's domain. Same-T lexical and heap bodies get separate deterministic
instance symbols. `CoreInstanceCloner` maps that incoming symbolic cleanup to
the exact existing `for_object(..., heap: true)` contract and sets the concrete
parameter's existing heap bit. Each inner owned call selects its heap ordinal
from the mapped source owner's cleanup. This existing path carries the original
domain transitively without another key field or a hop limit. Borrow-only
instances retain their prior key.

Core verifies actual/source/parameter cleanup and instance identity independently;
concrete heap instances independently reconstruct their finite transfer graph.
On a forwarded path, capture/commit disarms the outer slot and the inner exact
parameter acquires its original pointer and cleanup. A retained path keeps the
helper's normal-exit responsibility. Conditional cleanup uses the existing
current pointer, including null after a committed move.
Existing CFG acquisition/capture, SSA reconstructed object origins and native
`NativeObjectOriginPlan` correspondence enforce the same domain. The physical
owned Class PTR channel and backend remain unchanged. Scalar/void consumers
have no result-candidate channel. Direct incoming heap results have the separate
GEN-OWN-2C qualification below.

See [ADR 0095](../decisions/0095-finite-generic-heap-class-consumption.md),
[ADR 0096](../decisions/0096-finite-generic-heap-class-forwarding.md) and the
[independent forwarding mutation/native controls](../../tests/gen-own-2b/README.md).

## GEN-OWN-2C direct incoming heap Class results

One owned Ownable T formal may return directly once into a fresh named concrete
Class owner. The existing event proof annotates the returned-owner MOVE; its
structural summary excludes additional transfers/sites and loop returns, while
the existing path solver requires every reachable normal exit to transfer.
Consuming graph edges cannot qualify through an owned-result target.

Semantic local acquisition and the concrete origin prepass derive a generic
call's result domain from its matching verified actual owner. Shared generic
definitions remain neutral. Core rebuilds the return proof, exact substituted
actual/acquisition domain and fresh receiver from its own graph. Heap calls have
no candidate or forwarded result storage. Forged Checked eligibility does not
qualify a body.

The immutable definition/types/heap-formal key also determines result domain.
The specializer selects the exact heap cleanup for both incoming parameter and
result, maps direct return provenance to HEAP_OBJECT, and omits
CoreResultObjectStorage. Canonical instances verify result domain, cleanup and
candidate agreement independently. Same-T lexical results keep their existing
candidate and OWNED_PARAMETER_STORAGE provenance; Resource results keep their
existing pointer/release contract and recursion.

CFG's return capture precedes normal cleanup and clears the source. SSA requires
one exact heap RETURN event, independently reconstructs pointer/origin evidence,
and rejects callee cleanup of the escaped pointer. Its existing current-pointer
proof covers exact returned heap Class owners as well as record Resources.
NativeObjectOriginPlan retains the exact Class and heap bit with no candidate:
`(owner PTR, copied scalar neighbors...) -> PTR`. Existing LLVM lowering handles
the pointer and null-disarmed cleanup unchanged.

Heap result forwarding/recursion, generic owner locals in result helpers, inline producers,
multiple formals/sites, mixed domains within an instance, async/throws helpers,
foreign adapters and broader Q11 composition remain excluded. See
[ADR 0097](../decisions/0097-direct-generic-heap-class-results.md), the
[reviewed proof](../gen-own-2c-heap-result-design.md) and
[independent controls](../../tests/gen-own-2c/README.md).

## GEN-OWN-2D one incoming-owner local

Checked retains a distinct LocalSymbol with `generic_owner_source` pointing to
the exact owned T parameter slot. Its `incoming_parameter` stays null. The
declaration and move remain CheckedOwnedLocalDeclaration/CheckedOwnershipMove;
CoreBuilder independently checks the allocation-neutral source relationship.
No second parameter acquisition or concrete Class-storage guess is introduced.

GenericOwnershipFlow represents incoming-to-local transfer atomically in its
existing structured event tree. Local entry facts start disarmed, acquisition
moves the source and starts the destination, and RETIRE records normal scope
exit. The existing possibility-set evaluator checks reads and moves. Its finite
transfer summary composes one local edge with at most one call edge to a retaining
terminal; loops, multiple sites, cycles and local result helpers reject.

Core uses CoreOwnershipTransfer and the existing parameterized cleanup. Its
verifier reconstructs both owner identities, exact T/cleanup, initialization,
scope, signature, finite summary and terminal call from the Core graph before
and after specialization. The existing definition/types/heap-formal instance
key and cloner contract substitution give the local its incoming domain. The
instance retains the definition's local-source formal ordinal as body-shape
metadata; concrete verification must reconstruct the transfer and match that
ordinal independently. This metadata changes neither the key nor the ABI.
Caller-backed Class transfer is allowed only for this proved incoming/local
pair, with no local ObjectStorage. CFG independently checks the same physical
incoming acquisition, fresh destination and exact contract; its existing flow
disarms the source and retires the live local on each normal edge.

SSA transfer remains pointer definitions plus typed null for the source. The
existing owner-event/current-pointer authority now covers the incoming/local
pair for Resource and caller-backed Class as well as heap Class. Acquisition
must name the original owned parameter, exact producer or immediately disposed
source pointer. Unique acquisition and cleanup operands are independently
checked across joins. NABI retains its existing exact Class/heap origin plan;
LLVM erases verifier-only owner events. No runtime allocation-domain tag,
dictionary, new ABI, new object allocation or memcpy is added.

See [ADR 0098](../decisions/0098-one-generic-owner-local.md),
[the approved proof](../gen-own-2d-owner-local-design.md) and
[mutation/native/memory controls](../../tests/gen-own-2d/README.md).

## Stage lifetime and downstream boundaries

Qualification destroys Checked/Semantic symbols and requirements, verifies
parameterized Core, specializes both domains, verifies concrete Core, destroys
generic definitions, builds CFG, destroys Core, builds SSA, destroys CFG, and
builds NABI/CABI. Backend tests additionally destroy SSA after LLVM lowering and
verify the independent LLVM artifact. WeakRef assertions cover these lifetimes.

CfgBuilder's existing `CoreVerifier.verify_concrete` boundary rejects surviving
parameterized contracts and types. CFG ownership flow has no generic branch.
SSA, NABI and LLVM see only their existing concrete owner and result forms.
Generic definitions have no NABI; specialization precedes physical signature
planning. `relay<Resource>` uses `(PTR) -> PTR`; caller-backed `relay<Counter>`
uses `(candidate PTR, owner PTR) -> PTR`. A qualified direct heap Class result
uses `(owner PTR) -> PTR`. These use existing pointer channels and profiles.

Semantic/Core generic implementation has no LLVM dependency. The backend and
NABI implementations contain no Ownable logic. Generic specialization adds no
runtime witness, dictionary, type descriptor, ownership header, generic destructor
callback, type switch, heap allocation or box. Heap consumers reuse existing
Class destruction and allocator release; their caller already allocated the object.
No object bytes are copied or relocated. Existing cleanup order, OWNBOUND commit,
nullable ownership and non-unwinding traps continue to apply.

See [ADR 0060](../decisions/0060-generic-ownership.md),
[language](../language/generic-ownership.md) and qualification.
