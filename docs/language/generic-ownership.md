# Generic ownership

The current [structural generic contract](structural-generics.md) supports
declaration-derived owning fields, record graphs and qualified callable/member
channels. The GEN-OWN component profiles below document their original exact
domains; their exclusions do not override the later structural contract.

The separate [finite exact-Class bag](generic-class-bags.md) specializes one
qualified owning field and five direct members. It does not extend this guide's
generic free-function argument/transport domains or admit general generic owner
storage. Its concrete inspection helpers use the existing call-scoped loan rule.

Native classes containing [owned Resource fields](owned-resource-fields.md)
remain Ownable. `dispose<Context>`, `relay<Context>` and recursive forwarding use
the existing concrete object-owner contract. Relay performs no field-by-field
move or cleanup; final destruction cleans the current field values after user
deinit. Generic `owned T` fields and owned structs remain unsupported.

GEN-OWN-1 adds the built-in `Ownable` capability for explicit owned-binding and
ownership-transfer semantics:

```astra
void dispose<T>(owned T value) where T : Ownable {
}

owned T relay<T>(owned T value) where T : Ownable {
	return move value;
}
```

An owned parameter receives cleanup responsibility. On normal exit the function
cleans that owner unless it has moved responsibility to another call or returned
it. Transfer preserves the exact original resource handle or object storage.

## Ownable and transport modes

Ownable means a type can inhabit Astra's explicit ownership domain. It does not
answer whether an ordinary value can support future aggregate move semantics.
Copy and Move are not source capabilities in this milestone.

| Requirement on a parameter | Transport authority | Source value positions |
| --- | --- | --- |
| None, or Eq/Ordered/Numeric/Bitwise/Shift | PLAIN_COPY / GEN1_PLAIN_COPY | Existing plain parameters, results, locals and value transport |
| Explicit Ownable | OWNABLE, without GEN1_PLAIN_COPY | Owned function parameters/results, one bounded incoming-owner local, call-scoped borrowed parameters and compatible type-argument forwarding |

The exact case-sensitive Ownable identity belongs to the same capability
namespace as Eq, Ordered, Numeric, Bitwise and Shift. Types, values and members
do not participate in capability lookup. No capability implies another.
Ownable cannot combine with a value capability on the same T in GEN-OWN-1;
separate parameters may use independent requirements. Duplicate Ownable rejects
through the existing duplicate-capability diagnostic.

| Concrete category | Ownable |
| --- | --- |
| Nominal Resource/handle with the existing release contract | Yes |
| Native ClassType with transferable owned contracts | Yes |
| Class without deinit; empty class | Yes, including semantic lifetime responsibility |
| bool, integer scalars, f32, f64 | No |
| Numeric vectors and boolean masks | No |
| void*, typed pointers, arrays and slices | No |
| Ordinary struct; concrete generic struct instance | No |

Unconstrained `identity<Counter>` still rejects. Ordinary copyable records,
including `identity<Box<int>>`, are admitted by default plain-copy transport under
[ADR 0078](../decisions/0078-generic-copyable-values.md). The current
[argument authority](../../bootstrap/semantic/types.vala) delegates to the recursive
[copyability proof](../../bootstrap/semantic/copyability.vala); the exact Box call is
checked in [the semantic tests](../../tests/struct-abi/semantic.vala).
Class, Resource and whole-slice/array/buffer arguments remain excluded as plain T;
[current rejection cases](../../tests/gen-copy-1/negative.py) retain that boundary.
A `Box<T>` application rejects when T is Ownable because its fields require
plain-copy proof. A separate PLAIN_COPY U may appear in Box<U>, and a generic
owner function may use unrelated concrete Box<int> storage. See the
[copyable-value matrix](generic-copyable-values.md).

## Allowed contracts and operations

`owned T` requires an explicit Ownable requirement. Writing it without one
reports `owned T requires explicit capability Ownable`. Conversely, a plain T
parameter or result under Ownable reports that plain T value transport is
unavailable and requires `owned T`.

A move names an exact owned binding. It produces transfer authority for the same
T, not a copyable ordinary value. Bare copies, plain T locals,
generic null construction/comparison, member access, dereference and
address-of are unavailable. There is no way to construct unknown T.

Owned T fields in structs/classes and owned properties are deferred.
Concrete owner locals, concrete properties/methods and unrelated plain values
continue to use their accepted rules. An owned generic result may be acquired
by a legal concrete owned local at a caller, after its type arguments are known.
One generic local has the finite incoming-owner contract below.

## One named generic owner local

GEN-OWN-2D implements the user-approved Q11E Resource + exact Class domain:

```astra
void retire<T>(owned T value) where T: Ownable {}
int stage<T>(owned T incoming, bool send) where T: Ownable {
	owned T current = move incoming;
	if (send) { retire<T>(move current); return 1; }
	return 0;
}
```

The helper has exactly one Ownable type parameter, one owned T input and one
explicitly typed owner local. It is top-level, native, synchronous and
nonthrowing, with copied bool/integer/f32/f64 neighbors and scalar/void result.
The single local initializes immediately from the exact incoming owner outside
loops. No additional local owner or Class storage is admitted in this helper.
The input is disarmed and the local holds the identical pointer/handle. A
completed Q11A borrow is permitted. One optional direct consuming site may
transfer the local to a qualified retaining terminal helper; otherwise scope
exit or early return cleans the local once. An exit before initialization
retains cleanup on the incoming owner. A possibly moved local cannot be reused.

Exact heap Class ownership keeps its allocation, complete destructor/child
chain and one final free. Caller-backed/lexical Class ownership destroys without
freeing caller storage. Resource ownership releases the same handle. Existing
same-T heap/caller-backed instance keys select the cleanup statically; no object
copy, new allocation, runtime tag, dictionary or ABI profile is introduced.
Legitimate nullable incoming owners keep existing null-skipping cleanup.

Plain T, copies, default/null initialization, a second owner local/formal,
reassignment/rearm, local owned results, construction of T, result chaining,
loop/recursive transfers, persistent loans, generic members/aggregates,
subtype adaptation and foreign/async/throwing helpers remain excluded. In
particular, `return move current` remains illegal. Fatal traps do not unwind.
Q11 remains OPEN. See [ADR 0098](../decisions/0098-one-generic-owner-local.md),
[the approved proof](../gen-own-2d-owner-local-design.md) and
[qualification recipe](../../tests/gen-own-2d/README.md).

## Call-scoped generic borrowing

GEN-BORROW-1 permits one explicit `borrowed T` in a top-level synchronous,
nonthrowing native generic helper with `where T: Ownable`. Its other parameters
must be copied bool/integer/f32/f64 scalars; its result is a copied scalar or
void. The caller is synchronous too. Plain `T` retains its existing copy
semantics and remains unavailable under Ownable.

```astra
extern(C) void observe(int code);
void note<T>(borrowed T value, int code) where T: Ownable { observe(code); }
void forward<T>(borrowed T value, int code) where T: Ownable { note<T>(value, code); }
void inspect_then_dispose<T>(owned T value) where T: Ownable {
	forward<T>(value, 1);
	dispose<T>(move value);
}
```

Borrow a live exact-typed owning Resource/Class local or parameter, an incoming
`owned T`, or an incoming `borrowed T` being forwarded. Explicit type arguments
and existing named-argument inference work. Explicitly contextualized null and
nullable live owners retain their existing behavior; null supplies no new
inference rule. Generic Class calls do not adapt a Derived actual to a Base
type argument. Ordinary nonowning Class references, copied aliases, child-field
projections and inline owned producers are outside this first slice.

The call borrows the same handle or object storage without acquiring cleanup,
retaining, copying, moving or allocating its referent. The owner stays live
through argument evaluation and the invocation. Overlapping consumption rejects
in either order, including nested expressions. Once a nested borrow returns a
copied scalar, its loan has ended and a later argument may lawfully move the
owner. Existing branch/loop ownership proofs govern repeated calls and moved
joins.

Exact native Class borrows include lexical, caller-backed and heap owners, empty
classes and exact derived identities. Heap borrowing retains destruction/free
with the concrete owner. GEN-OWN-2A additionally supports the finite direct heap
consumer described below. GEN-OWN-2B adds finite heap consuming forwarding, and
GEN-OWN-2C adds a direct incoming-owner heap Class result as described below.

Ownable grants no member, property or comparison operations on unknown T.
Borrowed T can only forward through the bounded borrowed channel. Storage,
return, move/release, captures, async/coroutine use, generic members/classes and
C/GObject borrowing remain excluded. There is no runtime loan token, reflection,
dictionary, refcount, new ABI profile or object copy.

See the [approved lifetime argument](../gen-borrow-1-class-design.md),
[ADR 0094](../decisions/0094-call-scoped-generic-borrowing.md) and
[finite execution recipe](../../tests/gen-borrow-1/README.md).

## Heap Class generic consumption and finite forwarding

GEN-OWN-2A admits a named exact heap Class owner into one `owned T` under Ownable
in a synchronous, nonthrowing, top-level native consumer. Other formals are
concrete copied bool/integer/f32/f64 scalars; the result is scalar or void.
The caller is synchronous. Existing owner-name inference works, and the generic
call preserves exact nominal identity without a Derived-to-Base adaptation.

```astra
class Counter { init() {} }
void retire<T>(owned T value, int code) where T: Ownable {
	note<T>(value, code);
}
int main() {
	owned Counter lexical = Counter.init();
	var heap = new Counter();
	retire(move lexical, 1);
	retire<Counter>(move heap, 2);
	return 0;
}
```

The consumer acquires the original pointer and retires it once on normal exit.
Heap cleanup runs the existing complete destructor chain and deallocates the
object; empty/no-deinit Classes still owe deallocation. Lexical cleanup retains
its existing destructor-only responsibility. Same-definition/same-T lexical
and heap calls choose distinct compile-time instances; no runtime heap flag,
generic cleanup dictionary, refcount or hidden object copy is introduced.

GEN-OWN-2B additionally permits one structural forwarding site per helper, to a
qualified generic owned-T callee in an acyclic chain ending at a retaining sink.
A conditional path that does not forward retains cleanup responsibility in the
helper. Existing move state forbids later use; argument captures and commits
preserve original pointer and allocation domain across each transfer.

```astra
void relay<T>(owned T value, int code) where T: Ownable {
	retire<T>(move value, code);
}
void outer<T>(int code, owned T value) where T: Ownable {
	relay(move value, code);
}
```

Borrow-only T helper calls and scalar early returns are permitted. Heap generic
result forwarding, recursive/loop forwarding, multiple structural transfer sites,
generic owned T locals outside the bounded GEN-OWN-2D contract,
multiple owning T formals, inline producers, async/throwing/foreign consumers,
generic members/classes and persistent loans remain excluded. Existing live-owner
and overlapping-loan checks govern argument evaluation. Fatal traps remain
non-unwinding. Explicit null provides no named heap owner or heap instance key;
existing Resource/lexical null behavior is unchanged.

See [ADR 0095](../decisions/0095-finite-generic-heap-class-consumption.md) and
[ADR 0096](../decisions/0096-finite-generic-heap-class-forwarding.md), the
[forwarding lifetime argument](../gen-own-2b-heap-forward-design.md) and
[native/memory controls](../../tests/gen-own-2b/README.md).

## Direct incoming heap Class results

GEN-OWN-2C allows a top-level synchronous, nonthrowing native helper to return
its one incoming owned Ownable T directly. It may have copied concrete scalar
neighbors and completed call-scoped borrows. Exactly one structural
`return move incoming;` is permitted outside loops; every reachable normal exit
must transfer it. Existing explicit and supported inferred T calls work.

```astra
class Counter { init() {} }
owned T echo<T>(owned T value) where T: Ownable { return move value; }
int main() {
	var original = new Counter();
	var received = echo<Counter>(move original);
	release received;
	return 0;
}
```

The actual must be a named live exact heap Class owner. The result acquires
directly into a fresh named concrete owning Class local, using var or an explicit
owned Class destination. It carries the same allocated pointer and sole cleanup
responsibility. The former caller and returned formal are disarmed; the receiving
owner or later approved consumer performs complete destruction and one free.
Same-T heap and lexical applications retain distinct compile-time instances;
lexical candidates and Resource result contracts remain unchanged.

Returning a generic producer call, inline/nested consuming results, generic
owned locals in owned-result helpers, second result sites, loops/recursion, multiple owning formals,
subtype adaptation, async/throwing/foreign helpers and broader composition remain
excluded. Q11 stays OPEN. See [ADR 0097](../decisions/0097-direct-generic-heap-class-results.md),
[lifetime/ABI proof](../gen-own-2c-heap-result-design.md) and
[native and independent mutation controls](../../tests/gen-own-2c/README.md).

## Resource and caller-backed generic ownership forwarding

These existing forwarding examples admit Resource and lexical/caller-backed
Class ownership. Heap instantiation of either forwarding body remains excluded.

```astra
owned T forward<T>(owned T value) where T : Ownable {
	return relay<T>(move value);
}

void outer<T>(owned T value) where T : Ownable {
	dispose<T>(move value);
}
```

Outer T must explicitly satisfy inner's requirement. A future Counter or Resource
root cannot repair a missing requirement. Passing an owned result inline, such
as `dispose<T>(relay<T>(move value))`, remains unsupported. Direct result
forwarding introduces no temporary generic owner or object copy.

## Definition-time ownership flow

Generic parameters enter the existing OWNED possibility state. OWNED includes
legitimate nullable concrete owner capabilities; MOVED is a distinct unusable
state. There is no generic null flag. A move requires definitely OWNED, then
changes the source state to MOVED immediately at semantic capture.

```astra
void maybe_consume<T>(bool take, owned T value) where T : Ownable {
	if (take) { dispose<T>(move value); }
}
```

The take path transfers responsibility to dispose. The other path retains it and
cleans value at normal exit. Their join uses OWNED | MOVED, with the established
MAYBE_OWNED spelling. Moving value after that join rejects, since one path has
already moved it. A terminating arm does not contribute to later state.
Short-circuit operands and loop backedges follow the same possibility model.

Double moves, moved returns and possible moved uses reject without creating
Resource or Class instances, including in unused definitions. Concrete CFG
ownership analysis later handles only the specialized concrete operations.

## Results, recursion and storage provenance

```astra
owned T recurse<T>(int count, owned T value) where T : Ownable {
	if (count == 0) { return move value; }
	return recurse<T>(count - 1, move value);
}
```

Each recursive frame forwards one exact owner. Direct and mutual recursion reuse
the existing canonical instance registry. Returning an incoming Class owner is
safe because its storage comes from the caller or an ancestor. Callee-local
object storage still cannot escape through an owned result.

Class results retain OBJ-RET's caller-provided candidate storage. Forwarding an
incoming owner can leave that candidate unused. This physical mechanism is
selected after specialization and is absent from generic source semantics.
Resource results use their existing owner-pointer channel without candidate
storage. Neither case copies or relocates object bytes or duplicates a handle.

Concrete nullable owned results remain legal. For example a concrete
`owned Counter make_null() { return null; }` can supply a null owner to
`dispose<Counter>` or `relay<Counter>`. The same accepted concrete null-result
path exists for nominal Resources. Null final owners perform no cleanup.
Generic source cannot manufacture or test null T.

## Other values and cleanup order

```astra
U keep<T,U>(owned T owner, U value) where T : Ownable {
	return value;
}
```

U remains PLAIN_COPY, including int, f64, vectors and eligible ordinary records
under [ADR 0078](../decisions/0078-generic-copyable-values.md). Astra evaluates the complete
result before cleaning owners, then returns the captured result. Owner cleanup
uses the existing reverse lexical/declaration ordering. Strict floating-point
transport and non-contraction rules remain intact.

Moves capture responsibility left-to-right, including nested argument calls.
Physical disarming still commits immediately before invocation, after argument
evaluation. Traps do not unwind, including traps during result computation.

Generic definitions have no ABI. All capability evidence and parameterized
ownership contracts disappear before CFG. No witness, dictionary, type
descriptor, cleanup callback, destructor pointer, type switch, owner header,
boxing, heap allocation, new ABI profile or production dependency is introduced.

[ADR 0060](../decisions/0060-generic-ownership.md), [IR](../ir/generic-ownership.md)
and qualification specify and exercise these rules.

## Whole struct copy boundary

[Concrete struct copy](struct-copy.md) transfers no ownership. It snapshots
storage leaves and preserves source usability. The later
[plain-copy generic contract](generic-copyable-values.md) admits eligible records
and scoped Box<T> copies through the same authority; it leaves Ownable and owner
cleanup separate. No public Copy/Move capability or owned struct field is added.
Direct borrowed Ownable T and one incoming-owner local use the finite Q11A/Q11E
contracts above; broader composition remains deferred. The
[current rejection controls](../../tests/gen-buffer-1/negative.py) retain second-local and multiple-loan exclusions.
Future aggregate Move must remain distinct from Ownable. See
[Track B](../vision-and-roadmap.md#track-b).

Some compiler diagnostics retain historical milestone names or broad wording
such as `GEN1_PLAIN_COPY`. Read their accepted domain through the current
[source authority](../../bootstrap/semantic/types.vala), applicable later ADR and
rejection case. This guide correction changes no compiler diagnostic.

## Inferred generic ownership calls

[GEN-INFER-1](generic-inference.md) permits `relay(move resource)` and
`dispose(move context)` with the same exact Resource/Class arguments as explicit
applications. Inside an Ownable generic definition, `relay(move value)` may
propagate the exact outer T. Inference observes a move source without consuming it;
only the resolved valid call commits the ownership proof. Bare owners still reject.
Inline owned-result arguments retain the accepted explicit-call rejection; first
initialize a named owner from the producer, then move it. Direct Resource/Class
generic borrowing remains deferred; owned-array arguments use the separate buffer
contract below.

[Generic owned arrays](generic-owned-arrays.md) add a separate buffer contract on SliceType<T>. They do not expand Ownable or the independently approved Q11A/Q11E scalar-owner contracts.
