# Native object lifecycle

[Owned runtime-array fields](owned-runtime-arrays.md) follow the accepted owned
Resource field lifecycle: explicit definite initialization, receiver validation
before replacement production, live use during deinit, and cleanup of current
contents after normal deinit return. Resource and buffer fields form one reverse
declaration-order sequence. Deinit methods/scalar setters may replace them.
Constructor/deinit traps do not unwind or run deferred field cleanup.

[Owned Resource fields](owned-resource-fields.md) extend normal object
teardown: the user deinit body runs with live mutable fields and may replace
them directly or through methods/setters. Normal deinit return is followed by
automatic cleanup of the current final field contents in reverse declaration
order. This also occurs without user deinit. Move-out and explicit field release
remain forbidden. Traps do not unwind; a deinit trap skips automatic field cleanup.

[Computed property accessors](properties.md) require a fully live receiver.
Constructor `this.property` reads and assignments reject throughout `init`, even
after all fields have been explicitly initialized. Access through another live
object is allowed. Destructor `this.property` is allowed and observes final
state. Accessor-local resources and objects use ordinary lexical cleanup; brace
initialization initializes fields and never invokes setters.

[Owned object results](object-results.md) use the existing void constructor with an initializing caller-storage receiver. Construction completes before remaining callee cleanup; the returned object is excluded from that cleanup. Only the receiving owner destroys it. Traps remain non-unwinding, and no result-active flag or heap allocation exists.

[Transferable object owners](object-ownership.md) use these same constructors,
destructors and ObjectStorage identities. Unqualified construction retains fixed
lexical cleanup. `owned C` construction attaches cleanup to its unique owner
capability, which may transfer to a native parameter without moving bytes. A
nonnull callee owner deinitializes on normal exit unless forwarded; null skips
cleanup. Constructor owned object inputs clean before successful constructor
completion. All trap behavior remains non-unwinding.

[Borrowed object parameters](borrowed-object-parameters.md) carry a reference
without transferring, duplicating or delaying ObjectStorage destruction. A callee
can mutate the object and its eventual caller-owned deinit observes those changes.
`set(c); c = null;` still destroys the original storage exactly once at its lexical
end. Constructors accept `borrowed Counter source` through shared parameter rules;
source and newly constructed storage keep independent lifetimes. An explicit
source parameter may be null, unlike constructor `this`.

An explicit constructor initializes fresh lexical object storage. A declared
destructor runs automatically when that storage's lexical lifetime ends normally.
Reference aliases, assignment and nulling do not change this responsibility.

```astra
extern(C) int record(int value);
class Counter {
	int value;
	init(int initial) {
		this.value = initial;
	}
	void add(int amount) {
		this.value = this.value + amount;
	}
	deinit() {
		record(this.value);
	}
}
int main() {
	Counter c = Counter.init(40);
	Counter alias = c;
	c = null;
	alias.add(2);
	return alias.value;
}
```

The return expression reads 42, the destructor records 42 once, then main returns
42. Cleanup uses the original ObjectStorage, regardless of the current value of
`c`. Nothing is destroyed when `c` becomes null or when `alias` stops being used.

## Declarations and construction

```text
class-member := field-declaration | method-declaration | property-declaration
	| constructor-declaration | destructor-declaration
constructor-declaration := "init" "(" parameters? ")" block
destructor-declaration := "deinit" "(" ")" block
constructor-local := class-type identifier "=" class-type "." "init" "(" arguments? ")" ";"
```

A class has at most one optional `init` and one optional `deinit`. Neither has a
source result type. `void init()`, `Counter init()`, `void deinit()`, destructor
parameters, duplicate lifecycle members and ordinary class fields/methods named
`init` or `deinit` reject. Different signatures do not permit constructor
overloading. Named constructors and delegation do not exist. Structs do not gain
lifecycle members; existing ordinary struct methods retain ordinary semantics.

`Counter.init(arguments)` is a dedicated construction initializer whose class
must exactly match the new local. It is not static member dispatch or a general
expression. Assignment to an existing reference, return, call arguments,
conditional expressions and parenthesized construction expressions reject. The
new local is invisible during argument evaluation and becomes usable only after
successful constructor completion. Calling `.init` when no constructor exists
also rejects.

Object construction has no `new` or `delete` operation. BUFFER-1 separately uses
contextual `new T[count]` for runtime arrays. Lexical object construction does
not decide escaping ownership or heap allocation; `new` remains usable as an
ordinary function name outside that allocation form.

Classes without explicit constructors retain [complete brace construction](objects.md):

```astra
class Token {
	int code;
	deinit() { record(this.code); }
}
Token t = { code = 42 };
```

This activates one destructor after every field initializer completes. A class
declaring `init` must use it; direct braces reject with “cannot bypass explicit
init”. Constructors without user destructors are valid; classes with owned
Resource or buffer fields still emit automatic field cleanup.
Empty classes can have both lifecycle members and retain distinct object identity.

## The initializing receiver

Constructor `this` identifies exact caller-owned, nonnull storage under an
INITIALIZING receiver contract. It is immutable as a receiver binding and cannot
be copied into a ClassType local, rebound, returned, stored or used as an explicit
argument. It is not yet a fully live ordinary method receiver.

Every receiver field must be explicitly initialized exactly once on each
successful path. Constructor assignments to `this.field` mean initialization,
not ordinary mutation; no implicit zero or null field value exists. An RHS is
checked/evaluated before that write becomes initialized:

```astra
init(int initial) {
	this.value = initial;
	int already_initialized = this.value; // valid
}
```

Reading `this.value` before its initialization, including in its own first RHS,
rejects. A later second assignment rejects even when it would write the same value.

Conditional paths join both definite and possible initialization information:

```astra
init(bool choose) {
	if (choose) {
		this.value = 1;
	} else {
		this.value = 2;
	}
	int definitely_initialized = this.value;
}
```

Both branches initialize exactly once. Omitting one branch rejects at a later
read or normal completion. Writing after a one-sided initialization also rejects:

```astra
if (choose) { this.value = 1; }
this.value = 2; // possibly initialized twice
```

At a join, definite initialization is the intersection of reachable predecessor
sets, and possible initialization is their union. Reads need definite membership;
writes require absence from the possible set. Diagnostics name the constructor
and field. Unreachable completion paths, such as an infinite `while(true)` branch,
need no field completion. Literal unreachable branches and short-circuit operands
do not produce an uninitialized field load in emitted LLVM.

Receiver field initialization inside any loop rejects. Local calculations and
reads of fields initialized before loop entry remain valid:

```astra
init(int count) {
	int total = 0;
	while (count > 0) {
		total = total + count;
		count = count - 1;
	}
	this.value = total;
}
```

`this.method(...)` rejects throughout a constructor, even after field completion.
Ordinary free/native calls, locals, control flow, vector/DSP calculations, borrowed
slices and existing Resource ownership operations remain supported. Fields retain
OBJ-1 admissibility plus explicit owned nominal Resource and runtime-array fields;
vectors, typed pointers, object owners and plain Resource fields remain excluded. An explicit constructor `return`, including `return;`, rejects; successful
completion is body fallthrough only.

## Calls and successful construction

The caller reserves lexical ObjectStorage, evaluates explicit arguments left to
right, commits existing owned transfers immediately before the constructor call,
then invokes the constructor with the storage address first. Alloca placement is
not a source effect. Existing owned Resource parameters and borrowed Resource/slice
contracts reuse native call rules; explicit borrowed ClassType parameters now
share those rules, while owned object results use caller-provided storage under
OBJ-RET-1. Owned Resource and buffer parameters may explicitly transfer into
their matching owned fields.

The constructor physically returns void. On normal return the caller activates
the storage lifecycle and publishes the reference. If an argument traps, the
constructor is never entered. If the body traps, construction never succeeds.
Neither case runs that object's destructor. Constructor-local Resources and
objects use ordinary lexical cleanup before normal constructor completion.

## Destruction and lexical order

Destructor `this` is an exact fully initialized, live, nonnull, mutable receiver.
Field reads/writes and ordinary `this.method(...)` calls work under the existing
direct method contract. Objects and Resources declared in a destructor clean up
normally before it returns. Source cannot invoke `object.deinit()`, `this.deinit()`
or `ClassName.deinit()`, nor take the destructor as a value.

One successfully constructed ObjectStorage creates one cleanup responsibility.
`Counter empty = null;` and `Counter alias = c;` create none. Constructing storage A
then B and assigning `a = b` still destroys B followed by A, each using its final
field state. Outer objects remain alive when inner reference aliases leave scope.
Existing lexical provenance rules reject references that would outlive storage.

Objects share the Resource cleanup order. For declarations Resource A, object B,
Resource C, object D in one scope, cleanup runs D, C, B, A. Resource rearm keeps its
existing stable owner-slot rank; reference operations never change object rank.

| Exit | Required order |
| --- | --- |
| Ordinary fallthrough | Reverse order in the ending scope |
| `return expression` | Evaluate/preserve the result and transfer state, clean active scopes from inner to outer, return |
| `break` | Clean exited body/nested scopes, then leave the loop |
| `continue` | Clean exited body/nested scopes, then enter the next iteration |
| Normal body backedge | Clean the body before returning to the loop header |

Each loop iteration constructs a fresh semantic object lifetime, even when the
backend reuses a stack address after cleanup. A surviving reference cannot cross
that lifetime boundary. Destructor timing remains lexical even if no references
are used again; cleanup effects cannot move earlier merely because of liveness.

**Traps do not unwind.** A trap after construction does not guarantee any pending
destructor. A destructor that traps stops subsequent cleanup, including older
objects/Resources and its own local cleanups. This is not exception unwinding.

The compiler emits explicit direct cleanup calls. There is no runtime cleanup
stack, active flag, destructor registration, object lifecycle header, refcount,
GC or heap allocator. Layout and the internal native ABI remain compiler-private.

See [ADR 0050](../decisions/0050-native-object-lifecycle.md),
[IR](../ir/object-lifecycle.md) and qualification.
