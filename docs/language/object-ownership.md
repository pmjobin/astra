# Transferable lexical object ownership

For the later concrete heap-owner text facility, see [validated UTF-8
messages](utf8-messages.md). Its factory returns an independently allocated
unique Class through the existing checked heap-result channel, with ordinary
concrete child storage and receiver-bound inspection. It does not change the
caller-backed lexical ownership rules described below.

A class containing [owned buffers](owned-runtime-arrays.md) remains Ownable.
Its existing ObjectStorage and object PTR contracts are unchanged. OBJ-RET writes
buffer base/length directly into final field storage; forwarding and GEN-OWN
relay preserve the exact object and allocation addresses. Final destruction
cleans current fields once, in the shared Resource/buffer reverse order. This
adds no ClassType local/parameter reassignment or object relocation.

A class may now contain [owned Resource fields](owned-resource-fields.md).
Moving its owner transfers eventual field cleanup transitively while preserving
the exact ObjectStorage and field handles. No field-by-field move occurs. The
final object's normal destruction runs user deinit, then releases the current
owned fields in reverse declaration order. A null object performs neither action.
This does not permit owned ClassType fields or weaken object storage provenance.

[Property access](properties.md) through an owned object local or parameter is a
temporary nonconsuming receiver borrow. It works before move, does not transfer
the owner during assignment, and remains visible to the eventual destructor.
Use after move and consuming the captured receiver while evaluating a setter RHS
reject through existing ownership rules. Property values cannot be owned or
borrowed; all handle-valued properties are intentionally deferred to a later
ownership/borrowing property milestone.

[OBJ-RET-1 results](object-results.md) extend acquisition to `owned C c = make();`. The returned pointer may be null, candidate storage, or forwarded ancestor storage. OWNED includes a legitimate null capability and remains distinct from MOVED. Return move is allowed for incoming owned parameters; local storage, including a local result candidate, cannot escape.

`owned Counter` declares an ownership binding whose value still has exact
ClassType `Counter`. It owns one object's normal-exit cleanup responsibility.

```astra
class Counter {
	int value;
	init(int value) { this.value = value; }
	deinit() { record(this.value); }
	void add(int n) { this.value = this.value + n; }
}

void consume(owned Counter c) {
	if (c != null) { c.add(1); }
}

int main() {
	owned Counter c = Counter.init(41);
	consume(move c);
	return 0;
}
```

Here `record` is a declared recorder supplied by the program. The constructor
creates one lexical ObjectStorage. Consume receives its original address, mutates
it, and deinitializes it once with value 42. The caller's cleanup is disarmed.
The bytes stay in the caller's stack frame; no object is copied, relocated or freed.

## Two construction modes

| Declaration | Reference operations | Cleanup responsibility |
| --- | --- | --- |
| `Counter c = Counter.init(1);` | Ordinary copy, rebind and null assignment | Fixed to original lexical ObjectStorage |
| `owned Counter c = Counter.init(1);` | Temporary use and explicit consuming move | Unique, transferable owner binding |

The ordinary form keeps OBJ-1/OBJ-LIFE-1 semantics, even if the reference is later
null or points elsewhere. It cannot be passed as `move c` to a consuming parameter.
Both forms use the same ObjectStorage identity and the same DestructorSymbol.

```text
owned-object-local := "owned" class-type identifier "=" (fresh-construction | exact-owned-result-call) ";"
fresh-construction := exact-class-name ".init(" arguments? ")" | "{" field-initializers? "}"
owned-object-parameter := "owned" class-type identifier
owned-object-argument := "move" owner-identifier | "null"
```

Braces are permitted only without an explicit init, and require every field once.
`owned Counter c = { value = 42 };` is valid for such a class. Null, an ordinary
reference, another owner, and `move other_owner` are all invalid local initializers.
An owned binding cannot be assigned, rearmed or explicitly released. Parameter
bindings are also immutable, although the referenced object's fields are mutable.

## Moves, null and cleanup

An owner begins OWNED. Move requires definitely OWNED and changes the source to
MOVED at that argument's evaluation position. A moved source cannot be read,
compared to null, borrowed, accessed through fields/methods, or moved again.
After a conditional move, either kind of use also rejects at an OWNED | MOVED join.
Existing loop ownership rules apply: repeated unproven moves reject; a move
followed by break, or a fresh owner per iteration, can be proved safe.

An owned parameter may receive `null`, which owns nothing. A nonnull parameter
owns exactly one object lifetime. Null tests and ordinary guarded field/method
access work while the binding is OWNED. A directly constructed owned local is nonnull while owned; an acquired result may
be null.
Neither case creates a new ClassType. MOVED remains a source error even when its
physical slot has become null.

At normal cleanup, a nonnull owner invokes its exact destructor, if any. A null
capability skips cleanup. Classes without deinit still transfer semantic lifetime
responsibility. Nested scopes clean in reverse acquisition order. Root locals clean
before parameters; parameters clean in reverse declaration order, mixing objects
and Resources. Return expressions evaluate before cleanup.

```astra
void forward(owned Counter c, bool send) {
	if (send) { consume(move c); }
}
```

On the true path consume cleans; on the false path forward cleans. There is one
normal destructor responsibility, and no boolean active flag.

## Temporary borrowing

An owner may be used as a borrowed argument, method receiver or field base.
`inspect(c); c.add(1); c.value = c.value + 1; consume(move c);` is valid when
inspect expects plain `Counter` or explicit `borrowed Counter`. All mutations affect the same storage.
`Counter alias = c;` and assignment of c to an ordinary reference reject for
both local and parameter owners. Persistent aliases from owners remain deferred.

For `f(Counter view, owned Counter owner)`, `f(c, move c)` rejects, as does
the explicitly borrowed spelling. PARAM-BORROW-1 intentionally supersedes the
former same-call Class exception: the borrow must survive the invocation, during
which the owned input could invalidate its referent. `f(move c, c)` with the
reversed signature also rejects. Two borrowed inputs may still alias. A later nested consuming call cannot destroy an earlier outer
argument's temporary referent. Likewise `c.field = sink(move c)` rejects, as does
`c.method(move c)`, including consumption nested in an argument expression.

A borrowed input can alias an owned input of the same class. After forwarding the
owned input, such a borrowed input or its stored copies cannot be used unless
independence is proven. Current analysis is conservative across assignments.
Forwarding potentially aliasing borrowed and consuming inputs together rejects. A freshly constructed
separate object is independent. Ownership therefore never implies `noalias`.

## Calls and traps

Free functions, class/struct methods and constructors share owned parameter
machinery. The implicit receiver is still non-owning and nonnull. Consuming a
constructor input does not transfer or merge the new object's distinct identity.
Owned objects, Resources, borrowed objects, slices and vectors can coexist.

All arguments evaluate left-to-right. Semantic move occurs at the argument
position, but physical null/disarm commit occurs only after every argument has
succeeded, immediately before invocation. A later argument trap does not commit
transfer. Traps never unwind: neither caller cleanup on a pre-call trap nor callee
cleanup after invocation is guaranteed. A constructor trap after receiving an
owner follows exactly the same rule.

ObjectStorage transfer adds no heap allocator, reference count, GC, object
ownership header or ownership runtime. Owned buffer fields use their separately
qualified allocation/deallocation strategy. Unqualified/borrowed object results, local owner-to-owner moves,
owner rearm/release, stored borrows from owners and owned ClassType fields remain
deferred. See [ADR 0052](../decisions/0052-transferable-object-ownership.md) and
[object ownership IR](../ir/object-ownership.md).

## Ownable specialization

Native ClassType satisfies [Ownable](generic-ownership.md), including classes
without deinit and empty classes. A specialized generic owned parameter receives
the existing transferable object contract and exact incoming ObjectStorage
identity. Drop, conditional forwarding and recursion use the same null-disarming
and lifecycle rules. No object bytes are copied or relocated, and no generic
owned local construction, generic owned field or owned property is introduced.
