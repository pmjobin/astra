# Owned acquisition, transfer, release, rearm and cleanup IR

OWNBOUND-1 reuses these lexical obligations for owned Resource native parameter
slots. Entry acquisitions register parameters in declaration order, before root
locals; reverse rank cleans root locals first, then parameters in reverse order.
Nested scopes retain their existing inner-before-outer behavior. Argument transfer
keeps the caller slot but clears its pointer at call commit. An owned return
captures and disarms its source before remaining cleanups. No result-owner slot
or runtime cleanup registry is added. See [ownership boundaries](ownership-boundaries.md).

OWN-1 preserves cleanup responsibility separately from pointer values. It adds
no pointer type, NABI channel, SSA owner-state phi, or target runtime stack.

## Checked model and Core

CheckedCallExpression retains an optional OwnedValueProducer distinguishing
FOREIGN_OWNED_CALL and NATIVE_OWNED_CALL and advertises OWNED(cleanup) or UNMANAGED.
Its semantic type remains exact void* or HandleType. Native owned producers
require HandleType; nominal cleanup authority belongs to that type. The existing
CForeignOwnedResultContract remains the foreign binding input.
CheckedOwnedLocalDeclaration retains the exact LocalSymbol, checked producer or move,
cleanup contract, source span, and LocalSymbol.lexical_region. The analyzer
permits owner null comparisons and exact borrowed arguments, and rejects raw escape paths.

Core creates its own CoreCleanupContract registry in deterministic first-producer
order (nominal type contracts register with their handles). The immutable contract has an exact external symbol, symbol provenance,
and ordinal; its semantic signature is intrinsically void(void*). CoreCFunction
has an optional owned_cleanup reference. Generic descriptive metadata has its
semantic owned_result removed, allowing the original normalized metadata to die.

Each checked LexicalRegion maps to its corresponding CoreBlock through a
construction-time identity table. Existing block containment already expresses
lexical nesting, so no separate cleanup tree or SourceSpan inference is needed.
CoreOwnedLocal retains the ordinary scalar CoreLocalPlace and CoreCleanupContract
and weakly references its exact scope block. CoreFunction.owned_locals owns these
obligations. CoreInitialize.acquisition is the explicit Acquire marker: evaluate
the producer, initialize the pointer, then arm responsibility. It calls no runtime
acquire function. Core's verifier checks exact local, scope, contract, direct
producer, one initialization, and the owner-use capability restrictions.

## Structured Core → CFG

CfgBuilder uses a temporary stack of active CoreBlock scopes. Each scope records
owner slots in lexical declaration order, including fresh move destinations. Initializer lowering appends
the owner only after lowering value evaluation and pointer initialization.

| Transfer | Stack interval emitted, in reverse |
| --- | --- |
| Normal scope completion | Current scope |
| Return | All active scopes |
| Break/continue | All scopes deeper than the target loop's retained enclosing depth |

The loop target's existing exact identity selects its recorded depth, header,
and exit. Fallthrough cleans before the supplied continuation; transfer paths
terminate and do not also receive reachable fallthrough cleanup. Branch recursion
pushes/pops separate scopes, so one arm cannot add obligations to the other.
Emission does not mutate another path's active owner lists. Source tails are
represented in disconnected blocks, with no cleanup injected into earlier
reachable exits. SSA removes those tails through existing reachability.

Return lowering obtains the entire CfgValue, then emits CfgEvaluateInstruction
when cleanup is active, then emits cleanup and CfgReturn with the evaluated
value. This captures arithmetic as well as effects before cleanup. In particular,
a division trap in the return expression occurs before any destroy call.

CfgCleanupInstruction has a pointer CfgValue, exact CfgCleanupContract, and source
provenance. At each insertion point the builder supplies a normal CfgLoadValue
of the owner Place. The instruction is ordered, effectful, non-terminating under
normal foreign-contract assumptions, and has no result. Its meaning is: null
performs no call; otherwise invoke the exact cleanup on that pointer.

CFG owns an independent contract registry. Verification rejects foreign contract
identity, empty/duplicate targets, incorrect ordinals, non-void* operands, invalid
owned-result links, and reuse of an instruction in multiple ordered slots. The
contract's fixed signature has no mutable user-defined shape upstream of CABI.

## SSA

Owner pointer storage remains an ordinary promotable scalar Place. Initialize
and Load disappear through the existing scalar algorithm. SsaCleanupInstruction
consumes the exact current SSA pointer, references its own SsaCleanupContract,
and has no result. Multiple cleanup instructions retain their order relative to
calls, memory operations, arithmetic/traps, and other cleanups.

```text
%0 : void* = c-call create(...)
%1 : int = c-call effect()
cleanup %0 via #0
return %1
```

MOVE-1 adds explicit Core/CFG transfer events and a pre-SSA ownership lattice.
Each destination still has one declaration initialization. Same-contract rearming
changes its current pointer without adding or reordering a cleanup slot.
Transfer normalizes to destination=old-source and source=typed-null. Conditional
source values use ordinary pointer block parameters, never responsibility or
cleanup-contract phis. SSA verifier/dumper are standalone and have no VAPI, CABI,
LLVM, or LexicalRegion dependency. CFG/Core contracts may already have died.

## Physical cleanup and LLVM

CABI maps the exact SSA contract to CAbiCleanupFunction before body lowering.
It supplies the external symbol and fixed PTR-to-absent-result signature under
scalar-ptr-v1. Cleanup functions are distinct from Astra-callable imports.
Physical collisions reject; shared destroyers are declared once. Native NABI
and signatures are unchanged.

LLVM creates an external ccc declaration and lowers each cleanup as:

```llvm
%isnull = icmp eq ptr %resource, null
br i1 %isnull, label %cleanup.continue, label %cleanup.call
cleanup.call:
	call void @destroy(ptr %resource)
	br label %cleanup.continue
cleanup.continue:
	; subsequent instructions and the actual transfer
```

LLVM's printer omits default ccc; the backend explicitly sets and verifies the C
convention on declarations/calls. LlvmBlockState.end becomes cleanup.continue.
Later cleanups chain from it and branch/join/backedge phi inputs use the actual
physical continuation. This is the same authority used by division/null traps.
Completed artifacts retain LLVM handles and copied physical names, not upstream
contracts. No pointer or effect attributes are inferred.

**No trap cleanup or unwinding exists.** Guard failure still calls llvm.trap and
ends in unreachable. Cleanup uses call, never invoke. Explicit release extends
responsibility state before SSA; no ownership intent is inferred by recognizing
generated destroy calls.

## Cleanup after move

Transfer registers the fresh destination in the existing active lexical stack.
The source declaration and all its cleanup sites retain their exact contract,
including after conditional moves. OwnershipFlow accepts cleanup of every reachable responsibility set; it removes the owner from the active lifetime and rejects a second
cleanup on a dynamic path. It never rebuilds cleanup placement or elides cleanup.

Physical source nulling makes stale lexical cleanup harmless. LLVM's existing
constant builder may fold null == null, but still emits the guard and unreachable
call block. An actual-null resource transfers semantic responsibility while both
pointers remain null. A nested move can shorten destruction timing; return
expression ordering, reverse owner order and non-unwinding traps remain unchanged.
See [ownership flow](ownership-flow.md) and [moves](../language/moves.md).

## Cleanup after explicit release

Release remains a distinct checked/Core/CFG event and requires definitely OWNED.
It changes responsibility to RELEASED without ending the lexical lifetime or
altering cleanup sites. SSA emits the existing cleanup instruction at the release
position and then defines the owner pointer as null. Later lexical cleanup
consumes null and safely skips. A conditional release's ordinary pointer phi
selects null or the original pointer. An acquired actual-null pointer stays OWNED
until release, despite identical physical bits before and after.

Release can change physical destruction order intentionally. Release of b among
a, b, c destroys b immediately; automatic LIFO later physically destroys c, a.
CAbiCleanupFunction and LLVM's null-guard/physical-continuation logic are reused
unchanged. No runtime flag or new SSA instruction is required. See
[release IR](ownership-release.md).

## Stable lexical slots (REARM-1)

An owner binding is one cleanup slot with a fixed scope, ordinal, contract and
rank. The scope list above registers only declaration acquisitions and fresh
move destinations. Rearming never appends another entry. It supplies a new
resource after definite discharge and leaves every lexical cleanup site intact.

Automatic destruction is reverse lexical owner-slot order. Before rearming,
reverse acquisition and slot order coincided. With a=1, b=2, `release a; a =
create(3);`, explicit destruction is 1 followed by automatic b=2 and a=3: **123**.
Conditional rearming likewise cannot reorder slots. Every pre-REARM ordering
fixture remains unchanged. Cleanup uses the current pointer definition and its
existing null guard, including mixed resource/null phis. See
[ADR 0032](../decisions/0032-owner-rearming.md) and [rearm IR](ownership-rearm.md).
