# Ownership at native function boundaries

PARAM-BORROW-1 canonicalizes plain native HandleType/ClassType/SliceType
parameters to BORROWED_NOESCAPE before Core. Explicit and implicit spelling
produce identical checked and downstream contracts; no implicit-borrow node or
ABI behavior exists. Foreign UNMANAGED metadata and native result contracts
remain unchanged. See [ADR 0068](../decisions/0068-default-parameter-borrowing.md).

OWNBOUND-1 retains nominal value types, responsibility contracts and exact
cleanup authority independently of the physical pointer channel. Parameter
contracts are `UNMANAGED`, `BORROWED_NOESCAPE` and `OWNED_TRANSFER`; native result
contracts are `UNMANAGED` and `OWNED_TRANSFER`. Only nominal HandleType values may
carry native owned contracts. A HandleType's program-owned declaration supplies
its exact cleanup contract at every stage.

## Checked and Core authority

`FunctionSymbol` retains the result contract and exact cleanup. Each
`ParameterSymbol` retains its exact value type, ordinal and parameter contract.
An owned parameter has a `LocalSymbol` slot whose `incoming_parameter` identifies
the signature parameter and whose lexical region is the function root. This
slot is inserted into the body's value scope, so existing owner operations refer
to the current owner rather than rereading the immutable incoming value.

`CheckedOwnedArgument` contains its exact target parameter, cleanup and optional
`CheckedOwnershipMove`; absent move means explicitly owned null. Its span and
parameter ordinal retain provenance and argument position. Calls retain all
argument expressions in written order, binding unmanaged/borrowed arguments
through the existing exact target signature. `CheckedOwnershipReturn` contains
the exact HandleType/cleanup and either a source move or owned null.

`OwnedValueProducer` generalizes producer authority to `FOREIGN_OWNED_CALL` and
`NATIVE_OWNED_CALL`, each with exact semantic type and cleanup. Acquisition and
rearm consume either domain. No foreign metadata object is invented for a native
result and no per-native-function destructor symbol is required.

Core copies cleanup descriptors and retains contract enums independent of the
checked graph. `CoreFunction.owned_cleanup` identifies the native result contract;
its `result_contract` is the corresponding unmanaged/owned-transfer category.
`CoreParameter.pointer_contract` remains exact. Parameter slots are ordinary
promotable `CoreLocalPlace` objects with `incoming_parameter`, paired with the
existing `CoreOwnedLocal` obligation. Their entry statements are
`CoreAcquireParameter`, a constrained acquisition of that incoming value.

The `owned_locals` array includes parameter slots first in declaration order.
Its existing lexical scope machinery gives root locals later ranks and cleans
in reverse. `CoreOwnedArgumentValue` retains an exact source obligation (or null),
parameter and cleanup. `CoreOwnershipReturn` remains distinct from `CoreReturn`.
Core verification rejects ordinary owner copying, unconsumed owned calls, wrong
nominal types/contracts, non-root parameter slots and unsupported ownership types.

## CFG evaluation, flow and commit

`CfgAcquireParameter` establishes OWNED at entry and supplies the ordinary
`CfgParameterValue` as the slot's current pointer. It is a constrained
`CfgInitialize`, so ownership-flow initialization and SSA promotion reuse existing
machinery. Acquisition events form the entry prefix in owned parameter declaration
order, before user body instructions.

For a call with owned arguments, CFG retains these separate phases:

```text
argument 0 effects / evaluation
CfgOwnedArgumentCapture(pending(source, parameter, cleanup, type))
argument 2 effects / complete expression evaluation
CfgOwnedCallTransferCommit(call identity, pending transfers)
CfgCallInstruction(target, captured arguments, optional result)
```

`CfgPendingOwnedArgument` is a compiler value identity, never a runtime token.
Capture records its exact source (or owned null), parameter and cleanup. Ownership
flow requires OWNED at this event and immediately changes the source to MOVED.
Commit has no state transition: it authorizes the later physical null definitions.
Later arguments therefore cannot observe, borrow or move the source, even though
the pointer has not physically been cleared yet.

All argument trees finish before commit. Trapping arithmetic in a final argument
is explicitly evaluated first. Earlier null comparisons or other pure owner
reads are also captured before a later argument or operand containing a transfer.
Nested calls and short-circuit regions retain the same left-to-right rule.

The CFG verifier checks each pending value's unique preceding capture, exact
parameter contract, nominal type/cleanup, unique source, and exactly one use by
its committed call. Capture must dominate commit, including across expression
blocks. A path walk from capture to commit rejects lexical cleanup/release/rearm
or premature exits; this is an internal representation error. Commit must
immediately precede its exact associated call in the same executable block.
Deferred ordinary expression trees are forbidden at that committed call.

Native and foreign result values share the CFG immediate-consumption map, keyed
by exact result identity and cleanup contract. The next instruction must acquire
into a fresh owner or rearm an exact disarmed owner, with matching type and cleanup.
Raw stores, copies, discard, cross-block ownership consumption and inline chaining
reject. Return null is not an acquisition from an unmanaged producer.

## Returning through cleanup

`CfgOwnershipReturnInstruction` contains a `CfgOwnedReturnValue` with exact source
(or null), result type and cleanup. The source event requires OWNED and changes it
to MOVED. Only lexical cleanups may follow before its associated
`CfgOwnershipReturn` terminator in that block. This keeps return responsibility
explicit until flow validation completes.

The ownership lattice remains the same possibility set over OWNED/MOVED/RELEASED.
There is no pending or returned state, no lexical result-owner slot and no second
solver. Reachability, terminating predecessors and loop fixpoints remain existing
CFG analyses. Recursion needs no special state or ABI rule.

## SSA and physical erasure

At parameter acquisition, `current(slot)` becomes the incoming SSA parameter.
Move/release/rearm continue to push ordinary pointer/null definitions onto the
existing promotion stacks. Parameters do not become addressable solely because
they own; no ownership alloca is emitted.

At argument capture, SSA remembers the current source pointer in its temporary
evaluation map. It preserves that definition across subsequent argument effects.
At commit, the source's current definition becomes typed null. The associated
native call uses the remembered pointer. `SsaOwnedArgument` copies the exact target
parameter, captured SSA value, cleanup, source ordinal/provenance and committed
null definition as compile-time proof metadata. `SsaCallInstruction` records
native owned-result acquisition/rearm consumption. None are ABI values.

For an ownership return, SSA remembers the old pointer, defines null for the
source, lowers lexical cleanups against the resulting current values, and emits
`SsaOwnershipReturn` with the remembered result. This is an ordinary physical
return; ownership possibility sets are absent from SSA.

NABI remains `scalar-ptr-v1`: owned/unmanaged/borrowed nominal values use exactly
PTR and owned results use PTR. Its physical dumps are independent of ownership
contracts. LLVM receives ordinary `ptr` and unchanged `fastcc`, with existing
null-guarded destructor calls. No owner flags, runtime descriptors, destructor
pointers, refcounts or transfer tokens are emitted.

Checked boundary objects die after Core construction. Core descriptors die after
CFG construction; pending transfers and ownership analysis die after SSA. SSA
contracts and type tokens may die after LLVM construction. Weak callee links
prevent recursion from introducing compiler-object cycles. Standalone and stage
lifetime tests exercise these boundaries without upstream or LLVM dependencies.

Direct owned-call returns/arguments, C-owned exports, owned void* native boundaries,
aggregate ownership and contract-polymorphic ownership remain deferred. See
[ADR 0034](../decisions/0034-owned-native-boundaries.md) and
[the source rules](../language/owned-functions.md).
