# Borrowed native object parameters

Plain Class parameters and explicit `borrowed` parameters now share the same
contract. See [parameter borrowing](parameter-borrowing.md).

An [owned object binding](object-ownership.md) can be passed temporarily to a
borrowed ClassType parameter. Borrowing neither consumes nor disarms the owner.
Persistent aliases from the owner itself reject. `f(c, move c)` cannot supply
both a borrowed view and ownership from the same owner to one call; the reverse
order also rejects. PARAM-BORROW-1 intentionally supersedes the old exception. A nested consumer cannot end the earlier outer view's lifetime. Inside a
callee, borrowed inputs/copies that may alias a forwarded owner cannot be used
after its move. This conservative lifetime check preserves same-call alias safety;
no `noalias` attribute is implied by either parameter contract.

Use `Counter counter` or `borrowed Counter counter` to pass one nullable ClassType reference to a
native function. The callee can read and mutate the caller's object; the caller
keeps its reference, storage and destructor responsibility.

```astra
extern(C) int record(int value);
class Counter {
	int value;
	init(int value) { this.value = value; }
	deinit() { record(this.value); }
}
void increment(borrowed Counter counter) {
	counter.value = counter.value + 1;
}
int main() {
	Counter c = Counter.init(41);
	increment(c);
	return c.value;
}
```

The return value is 42 and the caller's eventual lexical deinit observes 42 in
the same ObjectStorage. No object is copied, allocated, moved or destroyed by
passing its reference. Nulling the original local after the call does not cancel
cleanup: `increment(c); c = null;` still destroys the original storage at its
ordinary lexical endpoint. Aliases do not add destructor responsibilities.

## Syntax and exact matching

```text
borrowed-object-parameter := "borrowed"? class-type identifier
```

The same syntax works in free native functions, class methods, struct methods
and constructors. Unqualified `Counter c` parameters borrow. `owned Counter c`
uses the separate [consuming contract](object-ownership.md). A borrowed parameter
of class A accepts only A or `null` contextualized as A.
Another class B, an identically shaped struct, `void*`, `Struct*` and numeric or
vector pointers cannot adapt to A. `Counter*` remains unsupported.

## Nullable, mutable and aliasable

```astra
bool is_null(borrowed Counter c) { return c == null; }
bool same(borrowed Counter a, borrowed Counter b) { return a == b; }
void set_pair(borrowed Counter a, borrowed Counter b) {
	a.value = 1;
	b.value = 42;
	// If a and b identify the same ObjectStorage, a.value is now 42.
}
```

`is_null(null)` is valid. Passing null has no allocation, provenance or entry
trap. `same(null, null)` is true; separately constructed same-state objects are
unequal, including zero-field objects. `set_pair(c, c)` is valid. Borrowing
provides neither readonly access nor exclusivity.

Field reads and writes retain ordinary null traps. A field write evaluates and
validates its reference before evaluating the RHS. `c.method(args)` validates
`c` before evaluating explicit arguments and invokes the exact static MethodSymbol.
Passing null as an argument is different: `f(null, effect())` runs `effect()` and
enters `f`; a later field or method use inside `f` may trap.

Parameter bindings are immutable, as for ordinary Astra parameters. `c = null`
rejects; `c.value = 42` is mutation through a reference and is valid.

## Local copies, forwarding and noescape

```astra
void helper(borrowed Counter c) { c.value = 42; }
void outer(borrowed Counter c) {
	Counter local = c;
	helper(local);
}
```

Copies preserve null or the exact reference identity, with no storage copy or
lifecycle responsibility. Forwarding and bounded recursive forwarding preserve
the same object. The caller can continue using fields, methods and identity
after a call that only borrows that object.

The callee's parameter is backed by function-region lexical borrow authority.
Local copies obey the existing conservative rule: their source authority must
outlive their destination, and subsequent reads summarize at the local's region.
A nested alias cannot be assigned back to an outer local even if it originally
received the parameter. Nonnull arguments to a borrow-only call stay live for the
whole invocation. An overlapping transfer of the same ownership capability
rejects because cleanup or forwarding could end that lifetime. Borrowing never extends storage beyond its construction scope.

Noescape forbids returning or storing the reference beyond this authority.
Unqualified/borrowed object-reference results, object-reference
fields, arrays/slices of references and pointers to reference slots remain
unsupported. There is no runtime borrow token, object descriptor, type tag,
refcount, or lifecycle metadata crossing the call. Source cannot call `deinit`.

## Methods, constructors and mixed boundaries

An explicit `borrowed Counter other` remains nullable even in a Counter method.
Implicit `this` remains an exact nonnull ReceiverType. A caller may pass its
receiver reference as `other`; the two may identify the same storage. Direct
`this == other` is deferred because `this` remains restricted to field and method
access, without conversion to an ordinary ClassType value.

A constructor may test, inspect, mutate or call methods on a borrowed source.
Its source stays live through construction; the newly constructed storage has
an independent lifetime. An object-reference field cannot capture the source.

Scalars, vectors, borrowed slices and owned Resource parameters/results coexist.
Arguments evaluate left-to-right. The object reference has no transfer commit;
existing delayed Resource ownership commit still follows all argument evaluation.

One exact ClassType value and the shared BORROWED_NOESCAPE contract survive
Core/CFG/SSA. NABI then maps that parameter to existing PTR. Simple functions
use scalar-ptr-v1; vectors select vector-v4 and slices select slice-v5. No
NativeObjectType or new profile exists. Physical PTR representation does not
merge semantic types. LLVM emits ordinary internal fastcc ptr parameters,
without object copies, parameter storage, destructor responsibility or new
`nonnull`, `noalias`, `readonly`, `byval`, `sret`, `dereferenceable` or `nocapture`
attributes. CABI and VAPI object boundaries remain unsupported.

See [ADR 0051](../decisions/0051-borrowed-object-boundaries.md),
[objects](objects.md), [borrowing](borrowing.md) and
validation.
