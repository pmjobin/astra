# Nominal enums and owning outcomes

ENUM-1 implements the approved E1-CONCRETE-VALUES subset. A closed nominal enum
has at least one variant. Constructors always qualify the type and use parentheses.

```astra
struct Header { int version; int size; }
enum HeaderResult { Ready(Header header), InvalidMagic, TooShort(int actual), }
HeaderResult validate(int magic, int size) {
	if (magic != 42) { return HeaderResult.InvalidMagic(); }
	if (size < 8) { return HeaderResult.TooShort(size); }
	Header header = { version = 1, size = size };
	return HeaderResult.Ready(header);
}
int status(HeaderResult result) {
	match (result) {
		case HeaderResult.Ready(header): { return header.version; }
		case HeaderResult.InvalidMagic(): { return -1; }
		case HeaderResult.TooShort(actual): { return actual - 100; }
	}
}
```

A declaration permits one trailing comma and has no trailing semicolon. Empty
variants may be declared with or without `()`. Fields use positional constructor
arguments, evaluated once from left to right with their exact contextual types.

Payloads may use existing scalars, whole supported vectors/masks, unmanaged
`void*`, eligible concrete copyable records (including fully instantiated generic
records), and acyclic nested concrete enums. Pointer copies do not own pointees.
Explicitly initialize enum locals. Assignment and native arguments/results copy
independent values; parameters are read-only independent snapshots. There is no
implicit zero/first variant or integer conversion.

`match` is a statement. It evaluates and snapshots its scrutinee once. Each arm
requires a block and never falls through. Cover every variant exactly once, or
finish with `else` covering the remaining variants. A fallback after complete
explicit coverage is rejected. `break` and `continue` refer to the enclosing loop.
All admitted arms participate in initialization and return checking.

Bindings are independent ordinary locals. Use all positional bindings, or name
every field, optionally in a different order:

```astra
enum Pair { Data(int left, int right), Empty }
int first(Pair pair) {
	match (pair) {
		case Pair.Data(right = _, left = value): { return value; }
		else: { return 0; }
	}
}
```

`_` discards a field only in a pattern. Visible names cannot be shadowed. Nested
enum fields require a nested match; guards, nested patterns and match expressions
are not supported. Only the same payload-free enum supports `==` and `!=`.
Payload enums have no derived equality, ordering, arithmetic, flags or hashing.

The approved ENUM-OWN-1 implementation adds explicitly applied generic enums
and owned array fields. Its full qualification remains partial; see the
implementation ledger. Enum fields in
records/classes, enum arrays/slices, borrowed scalar/record payloads, C imports/exports and VAPI enum signatures remain excluded. Surge 10
adds exact Resource, concrete heap Class and concrete owning record payloads, including an owned
`Utf8Message` with its own snapshot storage. Its scalar profile and current
qualification are described in [ADR 0139](../decisions/0139-enum-scalar-owners.md).

```astra
enum Error { Invalid }
enum Result<T,E> { Success(T value), Error(E error) }
enum VoidResult<E> { Success, Error(E error) }
enum ArrayResult<T,E> { Success(owned T[] value), Error(E error) }
ArrayResult<T,E> relay<T,E>(ArrayResult<T,E> input) { return move input; }
```

Type arguments are explicit on constructors and patterns, including phantom
parameters. Each exact ordered application has its own nominal identity. Plain
parameters require copied values; an owning enum cannot enter ordinary plain
`T`. A known enum signature imports only its exactly substituted declared
owned-array element premises, including requirements from nested enum fields.
A local declaration cannot introduce an unstated element premise.

An enum with any possible owning payload is move-only, including Empty/Error
values. Nested owning enums derive ownership in the same way. Declare these
values without an extra `owned` marker. A plain enum parameter consumes its
owner; pass a named owner with `move`, or pass a fresh constructor/result.

`match (state)` inspects a named owner. Copied fields are independent values;
owned-array and nested-owning fields are read-only, nonescaping arm views.
Length and element reads are allowed. Mutable forwarding, escaping a view,
replacement or movement of its root during inspection are rejected.
Scalar Resource/Class and owning record inspection currently requires `_`; use a consuming match
to bind an owner. A scalar payload constructor takes an explicit named move:

```astra
enum MessageResult { Ready(owned Utf8Message message), Empty }
owned Utf8Message take(MessageResult result) {
	match (move result) {
		case MessageResult.Ready(message): { return move message; }
		case MessageResult.Empty(): { var empty = new Utf8Message(""); return move empty; }
	}
}
```

A record field derives ownership from its declaration, so it needs no enum
`owned` marker. Construct it with a whole named move. A consuming match creates
an ordinary owning record binding that can be forwarded, returned, or used for
the supported field take/refill operations:

```astra
struct Packet { owned R resource; owned int[] bytes; int kind; }
enum PacketResult { Ready(Packet value), Empty }
```

Checked failure in a later payload argument preserves the original named
record. Record payloads use the same concrete synchronous value profile as
record parameters/results. See [ADR 0140](../decisions/0140-owning-record-enum-values.md).

`match (move state)` consumes a named owner; matching a fresh value also
consumes it. Bound owning fields acquire responsibility without extra syntax.
Ignored ownership is destroyed at arm entry in reverse field order; bound
owners clean in reverse initialization order when their scopes end.

Constructor arguments are captured once from left to right. Named moves reserve
sources until all arguments for that consumer are ready. A completed nested
consumer keeps its effects. Replacement constructs the incoming value before
cleaning the previous active payload. Cleanup follows only a valid live tag;
there is no public partial extraction, hidden heap box or reference count.

The ordinary optional library `base/outcomes.astra` declares the three families
above. Select it explicitly; the names have no special control-flow behavior.
The installed owning consumer is in `share/astra/examples/owning-enums` and uses
four files plus this explicit library source.

The installed four-file consumer is in `share/astra/examples/enums` relative to
the installation prefix (subject to configured `datadir`). Copy its files to a
working directory and run:

```sh
astrac types.astra validate.astra policy.astra main.astra -o header-example
./header-example
```

It handles Header records and nested DecodeError/LoadError alternatives through
native calls, returns, copies and exhaustive matches. The IR contract, native transport specification and accepted subset ADR are
maintained in the Astra repository documentation.
