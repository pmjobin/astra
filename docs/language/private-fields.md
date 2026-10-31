# Private native Class fields

Ordinary nongeneric native Classes can opt into lexical field privacy:

```astra
class Counter {
	private int count;
	init() { this.count = 0; }
	void increment() { this.count = this.count + 1; }
	int value() { return this.count; }
}
```

Only constructors, methods, property accessors and destructors declared on the
exact containing Class can access a private field. Such a member can also access
that field through another instance of the same Class. A derived Class's own
members have no access to its base's private fields; inherited base methods retain
their original declaring-Class access. Source-file proximity gives no privilege.

The rule covers reads, writes, indexing, length queries, synchronous borrows,
owner replacement, `swap` and named field initialization. The compiler rejects
unauthorized access before lowering. Existing unmarked fields retain their
current accessibility. Private fields retain the existing field-type,
constructor initialization, ownership, readonly and cleanup requirements.

`private` is contextual in a field declaration, before `owned` or `readonly`:

```astra
private owned u8[] bytes;
private readonly string label;
```

It does not introduce private methods, private properties, protected/friend/module
access, generic-Class visibility or a new storage domain. Other identifier uses
of `private` remain available. Privacy changes compiler declaration/access
authority; it adds no object header, runtime access flag, refcount or native ABI
version. It does not extend a borrow's lifetime or permit returning an owned
buffer field as a borrowed slice. Existing noescape and ownership restrictions
still apply even to an authorized member.

The [byte builder](utf8-byte-builders.md) uses private fields to protect its
backing owner and count. [ADR 0102](../decisions/0102-counted-utf8-byte-builder.md)
records the separately approved scope; [focused tests](../../tests/text-own-1b/README.md)
include an unrelated Class, cross-file refusals and independent stage faults.
