# Owned native object results

[Owned Resource fields](owned-resource-fields.md) initialize directly in the
existing caller-provided candidate storage. Fresh results, forwarding and
recursive relay preserve the same ObjectStorage, handle bits and eventual
cleanup responsibility. No object copy, relocation or new result ABI is needed.
Only final normal destruction cleans the current fields, after user deinit.

After `owned Counter c = make_counter();`, [computed property](properties.md)
access such as `c.value = 42;` uses the acquired nullable owner reference. It does
not relocate storage or transfer ownership; the eventual destructor observes
that mutation. No owned or ClassType-valued property result contract is added.

A native function or struct/class method can return `owned C`, where `C` is one
exact declared ClassType. `owned` is an ownership result contract, not a new type.
The result is nullable and must be acquired into a visible owned local or directly
forwarded from another function returning the same owned ClassType.

```astra
class Counter {
	int value;
	init(int value) { this.value = value; }
	deinit() { record(this.value); }
}
owned Counter make(int value) {
	return Counter.init(value);
}
int main() {
	owned Counter c = make(42);
	return c.value;
}
```

The caller reserves exact candidate object storage in its own frame. `make`
constructs directly there and returns its address. The factory creates no lexical
Counter storage, copies no object bytes and allocates no heap memory. The receiving
owner, or a later consuming owner, performs exactly one deinit.

## Bounded grammar

```text
owned-object-result := "owned" class-name
owned-object-acquisition := "owned" class-name identifier "=" owned-result-call ";"
owned-object-return := "return" class-name ".init(" arguments? ");"
                    | "return null;"
                    | "return move" owned-parameter-identifier ";"
                    | "return" exact-owned-object-result-call ";"
```

The underlying result remains exact `ClassType Counter` and carries the existing
owned-transfer result contract. Unqualified `Counter make()` and borrowed object
results remain unsupported. Constructors and destructors still return void.

`Counter.init(...)` is available as a complete fresh lexical initializer or the
complete owned-object return expression. It is not a general class-producing
expression: `use(Counter.init(...))` and `c = Counter.init(...)` reject. Brace
returns are deferred; a class needing fresh results declares an explicit init.
This also works for an empty class or a class without deinit.

## Nullable ownership

```astra
owned Counter maybe(bool enabled) {
	if (enabled) { return Counter.init(42); }
	return null;
}
void use() {
	owned Counter c = maybe(false);
	bool absent = c == null;
	inspect(c);       // borrowed nullable parameter
	consume(move c); // legal null ownership transfer
}
```

An acquired null is still a usable owner binding. OWNED represents responsibility
for a nullable pointer, just as for Resource results. MOVED is a different,
unusable state. Null comparison, temporary nullable borrowing and moving null are
legal before transfer. Every use of a moved binding rejects, including comparison
with null. Null cleanup is a no-op; field and method use retain their normal null
traps. Conditional ownership still uses the existing possibility-set analysis.

## Returning and forwarding existing ownership

```astra
owned Counter identity(owned Counter c) { return move c; }
owned Counter outer() { return make(42); }
owned Counter recursive(int depth) {
	if (depth == 0) { return Counter.init(42); }
	return recursive(depth - 1);
}
```

Incoming parameter storage belongs to an ancestor caller and survives the current
frame. Return move captures its pointer, disarms the parameter, runs remaining
callee cleanup, and returns the original pointer. Null parameters are legal.
Nested and recursive forwarding pass the same result candidate onward and return
the nested call's pointer unchanged. The nested result may be fresh, null, or
forwarded ancestor storage.

A callee-local object cannot escape, including an owned local acquired from a
result, which might point to its local candidate:

```astra
owned Counter invalid() {
	owned Counter local = Counter.init(1);
	return move local; // rejected: callee-local ObjectStorage cannot escape
}
```

Use `return Counter.init(1);` directly. Returning a fixed local, borrowed parameter
or `this` cannot manufacture ownership. Passing a same-class local owner through
`return identity(move local);` also rejects, because the callee may return it.
This is an exact storage-domain rule, not general lifetime inference.

## Candidate versus returned owner

| Returned PTR | Meaning | Cleanup target |
| --- | --- | --- |
| Candidate address | Fresh object constructed in caller storage | Returned PTR |
| Null | No object and no responsibility | No-op |
| Another address | Forwarded ancestor-owned storage | Returned PTR |

The candidate is reserved but not preinitialized. If unused, its bytes are never
read or destructed and it has no semantic object lifetime. There is no runtime
candidate-active flag, descriptor, storage tag, destructor pointer or object header.

## Ordering and companions

Constructor arguments evaluate left-to-right. Existing pending owned transfers
commit after argument evaluation, immediately before invoking init against the
result storage. Once init succeeds, remaining factory lexical cleanups run before
physical return. The returned object is excluded from callee cleanup. An argument,
constructor or later cleanup trap does not unwind and returns no owner.

Borrowed objects/slices, vectors and owned Resource arguments and locals use their
existing contracts. Methods have a non-owning receiver; a fresh same-class result
has an identity distinct from that receiver. An explicit owned parameter may be
returned by a method. Returning `this` remains invalid.

After acquisition an owner may be borrowed temporarily, mutated or moved into a
consuming parameter. `make().method()` and `consume(make())` are deferred until
owned temporary lifetimes have an explicit contract. Heap allocation, new/delete,
local owner moves, rearm/release, persistent aliases, owned ClassType/reference fields and
C/GObject results remain outside this milestone.

See [ADR 0053](../decisions/0053-owned-object-results.md) and
[object result IR](../ir/object-results.md).

## Generic ownership results

`owned T relay<T>(owned T value) where T : Ownable { return move value; }`
specializes to this result contract for ClassType. Incoming storage is
caller/ancestor-owned, so returning it preserves provenance. Direct generic
result forwarding threads the existing candidate storage; forwarding an incoming
owner may leave that candidate unused. Resource specializations receive no object
candidate. Generic source exposes neither storage mechanism. Generic owned locals
remain deferred and callee-local Class storage still cannot escape. See
[generic ownership](generic-ownership.md).
