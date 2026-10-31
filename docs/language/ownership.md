# Owned foreign handles (OWN-1 / MOVE-1 / OBORROW-1 / RELEASE-1 / REARM-1 / RESOURCE-1 / OWNBOUND-1)

[Local inference](local-inference.md) accepts exact owned producer results and
explicit moves: `var handle = open_resource();`, `var moved = move handle;`.
These create the same owning locals and cleanup responsibilities as explicit
`owned` declarations. Named owners without `move` still reject; no persistent
borrow is invented. Resource/buffer RAII replacement, release and cleanup order
are unchanged. Class ownership retains its existing result-storage limits.
Fields, parameters and results remain explicitly typed. PARAM-BORROW-1 separately
makes plain native Resource/Class/Slice parameters bounded borrows; `owned`
parameters and named `move` transfers remain explicit. See
[parameter borrowing](parameter-borrowing.md).

[Owned runtime arrays](owned-runtime-arrays.md) add unique cleanup contracts over
existing `SliceType<T>` with `owned T[]`. A fresh `new T[count]` zero-initializes
storage; native parameters/results and class fields can own the complete pair.
A borrowed slice never owns or frees its base. Named owners are move-only.

The separate [owned buffer exchange](owned-buffer-exchange.md) statement makes
ownership intent explicit with `swap(a, b);`. It permutes two initialized live
buffer owners without copying ownership or changing either declaration's cleanup
responsibility. Resource/Class owner exchange and general field extraction remain
outside its scope; ordinary transfers continue to require `move`.

Assignment to a live mutable concrete Resource or buffer local/parameter is RAII
replacement. The incoming owner is produced and captured before source transfer,
old-value cleanup and complete destination storage. RHS traps leave the old
owner untouched. Assignment to MOVED/RELEASED storage rearms without old cleanup.
Explicit release remains intentional early destruction. The same slot, cleanup
rank and OWNED/MOVED/RELEASED authority apply throughout. ClassType replacement
is not generalized, and legacy producer-specific owned void* retains its prior
rearm restriction. See [replacement and rearm](rearming.md).

[Owned Resource class fields](owned-resource-fields.md) are persistent owner
slots separate from Resource type identity. Constructor transfer initializes
them exactly once. Replacement validates the receiver, captures the incoming
owner, consumes its source, releases the old handle and stores the new handle.
Non-consuming use borrows temporarily; move-out and explicit field release reject.
Normal object destruction runs user deinit first, then cleans final field values
in reverse declaration order, including replacements performed during deinit.
Struct owners, class-owner fields and generic owner fields remain deferred.

GEN-1 [generic functions](generic-functions.md) can contain existing concrete
owned Resource/object parameters and locals, with ordinary moves, borrowed calls,
returns and cleanup ordering. Their exact parameter, owner and storage identities
are mapped during Core specialization. T itself has GEN1_PLAIN_COPY capability
and no ownership responsibility. `owned T`, `borrowed T` and handles, classes,
slices or typed pointers as generic arguments remain deferred.

[OBJ-RET-1](object-results.md) adds owned ClassType result producers to the shared ownership framework. Acquisition, nullable OWNED state, moves and cleanup reuse OWN/MOVE/OWNBOUND. Object results add exact storage provenance and caller candidate storage; callers destroy the returned owner PTR. Local owner moves, rearm/release and persistent aliases remain unsupported.

[OBJ-OWN-1](object-ownership.md) extends the same ownership framework to explicitly
fresh `owned ClassType` locals and consuming native parameters. Underlying values
remain exact ClassType. Move invalidates the source semantically at argument
capture and commits physical null disarming immediately before invocation. The
callee owns exact ObjectStorage/destructor responsibility, without copying or
relocating storage. Root/local cleanup order is shared with Resources. Object
owners permit temporary borrowing and mutation, but no persistent aliases,
ordinary reassignment, rearm, release, local move destinations or borrowed/unqualified object results.

[Borrowed ClassType parameters](borrowed-object-parameters.md) carry no ownership.
`process(c, move resource, effect())` evaluates in source order; the object value
has no commit, while Resource transfer commits after all arguments evaluate.
Owned Resource parameters/results coexist with borrowed objects even though both
physically use PTR. ClassType reference copies create no cleanup slot and never
transfer, duplicate or extend ObjectStorage destructor responsibility. Caller
cleanup keeps its original rank and observes callee mutations.

[Lifecycle callables](object-lifecycle.md) share native Resource contracts:
constructor owned parameters receive ordinary committed transfers and clean at
constructor root exit; borrowed Resource/slice inputs remain nonescaping.
Arguments evaluate left to right before the transfer commit immediately preceding
init. Object cleanup activates only after init returns. Constructor/destructor
locals, including nested objects and owned Resources, use the same cleanup list.
Resource rearm retains its stable owner-slot rank; reference changes never alter
an ObjectStorage rank. STRUCT-COPY adds no Resource-bearing structs or owned struct fields.

OBJ-1 [object references](objects.md) are nullable lexical borrows of separately
identified object storage. They are not owned Resource handles. Copying, rebinding
or setting a class reference to null performs no retain, release or destruction.
A declared destructor belongs to the construction's storage identity, which
survives reference rebinding until its lexical scope ends. ObjectStorage actions
and Resource owner-slot actions share one lexical LIFO cleanup planner. Return
expressions and transfer state are preserved before cleanup; break, continue and
backedge clean their exited scopes. Traps, including destructor traps, never unwind. Borrowed/unqualified object results and heap ownership remain deferred; explicit `owned C` is covered by OBJ-OWN-1. Plain and explicit borrowed ClassType parameters carry no cleanup responsibility.
Class methods reuse supported owned Resource signatures and transfer commits.
A nullable class receiver validates before any explicit argument, including owned
capture; with a valid receiver the existing evaluation and commit rules apply.

[Struct methods](methods.md) reuse native owned Resource parameters and results.
`object.consume(move resource, later())` prepares the non-owning receiver first,
captures explicit arguments left-to-right, then performs the existing transfer
commit immediately before invocation. The receiver struct is never transferred
or given cleanup responsibility. `owned Resource make(...)` method results use
the same producer consumption, exact cleanup and forwarding rules as native
functions; release/rearm and borrowed-slice parameters remain compatible. METHOD-1
changes no ownership state machine, cleanup rank or trap behavior and introduces
no struct destructors, object ownership or runtime metadata.

[Owned native functions](owned-functions.md) extend these same owner operations
to `owned Resource` parameters. Parameters start OWNED in stable function-root
slots; root locals clean first, then parameters in reverse declaration order.
`consume(move r)` transfers responsibility to a callee. `return move r` transfers
it to the caller of an `owned Resource` function, clearing r before cleanup.
Literal null is permitted directly at either boundary. Bare owned void* native
boundaries remain unsupported.

RESOURCE-1 also permits `owned Resource` for an imported [nominal handle type](resource-handles.md).
Its exact cleanup contract comes from the type declaration. Every rule below for
acquire/move/borrow/release/rearm, nullness and lexical rank applies to either
owner value type. The following void* examples continue to demonstrate the
compatible producer-specific contract path.

An owned local holds a nullable foreign address and one cleanup responsibility:

```astra
int scoped() {
	owned void* resource = create_resource(1);
	if (resource == null) {
		return 0;
	}
	return 7;
}
```

The producer must be declared through [VAPI owned-result metadata](../vapi/owned-results.md):

```text
[CCode(cname = "resource_create_impl", destroy_function = "resource_destroy_impl")]
void* create_resource(int id);
```

The supplied C implementation must return a handle compatible with exactly
`void resource_destroy_impl(void*)`. The destroyer is a physical contract, not
an Astra source callable. An ordinary unannotated void* producer cannot initialize
an owner. Header metadata does not validate or provide either implementation.

## Grammar and acquisition

```text
owned-local-declaration := "owned" type-name identifier "=" owned-initializer ";"
owned-initializer := direct-owned-result-call | "move" identifier
```

`type-name` must resolve exactly to `void*` or an imported HandleType. The initializer is either a direct
annotated foreign call, native owned Resource call, or an explicit [move](moves.md) from an exact owner. Parentheses may group that same call, as in
`owned void* h = ((create_resource(1)));`; they preserve ownership classification.
Arguments cannot themselves consume owned results. A direct `move owner` may
transfer to an exact owned Resource native parameter. A compatible borrowed parameter may temporarily
receive an owner. Unmanaged native producers, literal null, copied owners, and other raw
expressions cannot initialize a local owner.

Successful return establishes responsibility even when the pointer is null. The
local is visible only afterward. Pointer type/representation remains ordinary
void*: ownership belongs to expression category and binding obligation. There is
no acquire runtime call and no heap/refcount machinery.

## Permitted observation and rejected escapes

The four direct owner comparisons are `h == null`, `h != null`, `null == h`, and
`null != h`. Their bool results can participate in ordinary expressions,
short-circuit conditions, function arguments, and returns. Comparing the owner
with another pointer/owner is unsupported. These observations require definitely
OWNED state; MOVED, RELEASED and mixed possibilities reject even when physically null.

The following forms reject before Core:

```astra
void* raw = create_resource(1); // owned result cannot enter raw storage
create_resource(1);            // owned result cannot be discarded
use(create_resource(1));       // nested acquisition cannot lose responsibility
owned void* b = h;             // copying responsibility is unsupported; use move h
void* alias = h;               // no unmanaged alias
h = null;                     // rearm requires an owned producer; discharge uses release h;
use(h);                       // ordinary use(void*) has no noescape contract
return h;                     // an owned Resource result requires return move h;
```

`owned int`, `owned bool`, `owned Pair`, and `owned Pair*` reject. The `owned`
qualifier on fields is limited to Resources and BUFFER-1 runtime arrays; native
Resource, buffer and ClassType parameter/result contracts are documented separately. Imported
owned Handle results are supported. There is no delete, free or take source
operation. Concrete Resource/buffer moves support owned-local initialization,
replacement, native owned arguments/results and owned field inputs.
[Release](release.md) is the statement `release h;`
for a definitely OWNED local or owned Resource parameter; it invokes the exact cleanup and ends responsibility.

Same-contract [rearming](rearming.md) permits assignment after definite discharge;
concrete Resource/buffer live destinations instead perform automatic replacement.
Move assignment, contract changes and longer-lived aliases remain future work. Ordinary void*
parameters may retain or invalidate handles, so automatic decay into calls
would be unsound without a declared non-retaining contract.

## Deterministic lexical cleanup

Cleanup follows reverse lexical owner-slot order, including fresh move destinations.
If a scope declares a, b, then c, it cleans c, b, then a, regardless of rearming. Exiting nested scopes cleans inner owners
before outer owners. Root owned parameters rank before root locals, so they clean
last in reverse parameter declaration order. Each dynamic execution of a loop-body declaration acquires
its own obligation, even though the source local has one static identity.

| Exit | Owners cleaned before transfer |
| --- | --- |
| Normal block end | Owners acquired in that block, in reverse order |
| Function return | Every active owner, inner to outer |
| Break | Body/nested owners up to the selected loop's enclosing scope |
| Continue | Body/nested owners before reevaluating that loop's condition |
| Loop-body fallthrough | Body owners before the backedge |
| Branch join | Owners of the executed arm only |

`return effect();` evaluates effect and the entire result expression first,
then cleans owners, then returns the computed value. This includes memory reads
and trap-capable arithmetic. Enclosing owners survive a break or continue that
leaves their scope active. Source after unconditional transfers may be preserved
in unreachable IR; it cannot acquire or clean resources on reachable paths.

A null owner has the same lexical obligation, but cleanup invokes no destroyer.
Binding authors need not provide destroyers that accept null. Unused owners
still acquire and clean: both producer and destroyer are observable effects.

**Traps do not run cleanup.** Division by zero, null Struct* access, and
llvm.trap terminate abnormally without unwinding. Foreign code that never returns
also prevents subsequent Astra cleanup. Normal-exit guarantees must not be
interpreted as exception safety or crash cleanup.

The compiler materializes cleanup instructions on control-flow exits. The
program has no runtime stack of destructors or hidden ownership metadata.
Native Struct* borrowing remains governed independently by [BORROW-1](borrows.md).
See [ADR 0028](../decisions/0028-owned-foreign-handles.md) and [cleanup IR](../ir/cleanup.md).

## Transfer preserves lexical cleanup

`owned void* b = move a;` transfers a's exact contract and responsibility to b,
then makes a semantically MOVED. Cleanup still visits b then a; source null
clearing makes a's cleanup a no-op. A conditional move may leave a MAYBE_OWNED,
which permits compiler cleanup but no source reads. A nested destination can
shorten resource lifetime. A real null resource can still move: ownership state
and pointer nullness are independent. See [moves](moves.md) and
[CFG ownership flow](../ir/ownership-flow.md) for joins, loop fixpoints and diagnostics.

## Temporary owner views

[Borrowed parameters](borrowed-parameters.md) permit `inspect(h)` when the target
parameter is `borrowed void*` or a native plain/explicitly borrowed exact Handle. The exact owner must be OWNED; the call leaves it
OWNED and preserves its cleanup contract, ordinal and scope. Repeated calls,
null-valued owners, borrowing before a move and borrowing a moved destination
are valid. There is no general owned-to-raw conversion or inline borrowing of an
owned result. Borrowing introduces no cleanup suppression or runtime machinery.

## Explicit early discharge (RELEASE-1)

`release h;` requires definitely OWNED and changes h to RELEASED without
transferring responsibility. An OWNED null may be compared, borrowed and released;
a RELEASED null is unusable. Double release, move/borrow after release and release
of a moved source reject. A moved destination may release, and completed borrows
may precede release. The disarmed slot may subsequently be [rearmed](rearming.md) with the same contract.

Release destroys a non-null pointer at its statement position and defines physical
null afterward. Lexical cleanup still visits the owner but no-ops. This may change
physical destruction order intentionally, while automatic cleanup retains its
existing LIFO/control-flow behavior. Conditional release joins `{OWNED, RELEASED}`;
both releasing arms join `{RELEASED}`. Return/break/continue use actual CFG edges,
and loop fixpoints reject a possible second release. No runtime ownership flag or
ABI change is needed. See [release](release.md) and [release IR](../ir/ownership-release.md).

## Exact-width integers beside owners

INTS-1 permits all six [integer types](integers.md) beside owned and borrowed
Resource values, including native parameters such as
`int process(owned Resource r, u8 mode, u16 count)`. Integer literal type probing
has no ownership or evaluation effects. Argument evaluation, moves, pending
transfer commit, rearming, and reverse cleanup retain their existing order.
The new native integer channels coexist with PTR under scalar-int-v2. Resource
handles remain pointer-like nominal types, never integers; no conversion or
integer truthiness applies to them.

## Explicit generic capabilities

Named generic capabilities leave T non-owning under GEN1_PLAIN_COPY. There is no
source Copy or Move requirement and no owned/borrowed T. Concrete owned Resource
and object parameters/locals inside a constrained generic retain exact transfer
and cleanup order, including evaluation of a return expression before cleanup.
Generic ownership remains deferred. See [generic capabilities](generic-capabilities.md).

## Generic native structs

GEN-STRUCT-1 aggregate construction does not give T ownership or aggregate Copy/Move authority. Box<T> may coexist with already accepted concrete owned or borrowed responsibilities inside a generic function. owned T, borrowed T, aggregate generic arguments and whole-struct responsibility transfer remain deferred. No allocator, heap box or runtime generic descriptor is introduced. See [generic structs](generic-structs.md).

## Generic owned contracts

[GEN-OWN-1](generic-ownership.md) permits `owned T` function parameters/results
only with explicit Ownable authority. A generic owner can be moved, forwarded,
returned from an incoming parameter, or dropped on normal exit. Definition-time
checking rejects double/possible moves before specialization. Resource instances
reuse these exact release, null, cleanup-order and non-unwinding rules. There are
no generic owned local declarations, fields, properties or borrowed T.

## Copyable native storage

[Whole native struct copy](struct-copy.md) is an ordinary Place-to-Place operation
for recursively copyable storage. It leaves the source initialized and transfers
no cleanup responsibility. Current legal struct fields carry no ownership contract;
assignment overwrites those copyable leaves after a complete snapshot. This does
not define overwrite behavior for future owning aggregates. Resource and ClassType
are excluded from the recursive copyability rule. Ownable is unchanged; aggregate
Move, owned struct fields and source Copy/Move capabilities remain deferred.

## Multi-source composition

[Source-file boundaries](source-files.md) have no ownership or lifetime meaning.
Native Resource/Class/slice parameters use the same bounded borrowing contracts;
named ownership transfers remain explicit `move`. Foreign/VAPI authority, owned
Resource/buffer fields, cleanup order, generic Ownable and object result storage
are unchanged. Ownership analysis operates per function over exact globally
resolved callees. No whole-program ownership inference or runtime table is added.

## Generic call inference

[GEN-INFER-1](generic-inference.md) can remove redundant generic type arguments
from `relay<Resource>(move resource)`, yielding `relay(move resource)`. Exact
Resource/Class identities and outer Ownable parameters are supported. Named
transfer remains explicit with `move`; failed inference or call checking commits
no enclosing ownership proof. Existing cleanup, borrow, ObjectStorage and direct
owned-argument restrictions remain the authority.

Direct generic array owners use the same moves, incoming-first replacement, release/rearm and structured cleanup described here. See [generic owned arrays](generic-owned-arrays.md); element copying and allocation ownership remain separate.
