# Owned Resource fields

[Owned runtime arrays](owned-runtime-arrays.md) separately extend this field
authority to complete buffer owners. Their
[exchange statement](owned-buffer-exchange.md) can permute two initialized buffer
slots while preserving field initialization and cleanup order. It does not admit
Resource-field exchange or change the field move-out restrictions below.

A native class can hold a persistent owner slot for an exact nominal Resource:

```astra
class Context {
	owned BufferHandle buffer;
	int count;
	init(owned BufferHandle buffer) {
		this.buffer = move buffer;
		this.count = 0;
	}
}
```

`BufferHandle` is an existing nominal Resource, normally declared with its release
contract in VAPI. The `owned` modifier is required. It describes responsibility,
not a new semantic type. The field stores the existing handle representation.

Only native class Resource fields are added. Plain Resource fields, owned raw or
typed pointers, owned classes/structs/scalars/vectors/arrays/slices, Resource
fields in structs, and generic `owned T` fields remain unsupported. Existing
scalar/value class fields and the copyable struct model are unchanged.

## Construction

A class with owned Resource fields requires explicit `init`. Every field must
initialize exactly once on every normal completion path. Reads and borrows
before initialization, missing initialization, possible duplicate initialization,
and initialization in loops reject under the existing constructor analysis.
Unreachable normal completion requires no initialization. No implicit null field
initialization or acquisition through brace construction is added.

`this.buffer = move buffer;` transfers the named input's exact type and release
contract. The input becomes MOVED and constructor exit does not clean it again.
A direct compatible owned-result call also works:

```astra
init() { this.buffer = make_buffer(); }
```

There is no cleanup of an uninitialized destination. Source evaluation order is
preserved. Constructor traps do not unwind: already initialized fields and
pending constructor-local owners receive no newly invented rollback cleanup.

## Temporary use

A live field can supply an existing `borrowed R` parameter directly:

```astra
use_buffer(this.buffer);
if (this.buffer != null) { use_buffer(this.buffer); }
```

This is a temporary, non-escaping borrow, not an owner copy. The exact source
field and containing object remain authoritative. Borrowed fields cannot become
unmanaged locals, stored references, or borrowed results. No new borrowed-return
contract is introduced. Existing null comparisons do not consume the field.

A field borrow cannot overlap passing a potentially aliasing containing-object
argument or method receiver to that call. Nor can a later argument call access
that ClassType while the field borrow is pending: replacement could invalidate
the captured handle. This is conservative for separate objects of the same type.
Finish the Resource call before passing the object to another call. Multiple
field borrows and later plain scalar field reads are permitted. Object-only
borrowed aliases remain mutable and may alias each other.

## Replacement

After construction, direct assignment, methods and existing property bodies may
replace a field using an exact named owner or direct owned result:

```astra
this.buffer = move replacement;
this.buffer = make_buffer();
```

The order is part of the language contract:

1. Evaluate and validate the receiver/destination.
2. Evaluate and capture the incoming owner completely.
3. Consume the incoming named owner's responsibility, if any.
4. Load the old handle and release it exactly once if non-null.
5. Store the captured incoming handle.

A null receiver traps before incoming evaluation or consumption. A producer
trap leaves the old destination untouched. Incoming side effects precede old
release, and the new handle is stored only after release. No equality guard is
added for illegally duplicated ownership. Named sources are MOVED afterward.
Other aliases of the same live object observe the replacement.

The field remains initialized. `move this.buffer`, field-to-field move,
self-move, and `release this.buffer` reject because they would leave an empty
persistent slot. Owned Resource-valued properties are not introduced; a scalar
property setter may call a concrete owned Resource producer inside its body.

## Destruction, deinit, and null

Normal containing-object destruction automatically cleans its owned fields,
even without user `deinit()`. User deinit runs first with live mutable fields.
It may borrow fields and perform ordinary replacements directly, through
methods, or through legal setters. Automatic cleanup then releases the current
final contents in reverse declaration order. Interleaved scalar fields do not
participate. For fields a, b, c, destruction is user deinit, c, b, a.

Replacing A→B→C releases A at the first replacement, B at the second, and C at
normal final destruction. The same rule holds inside deinit. A trap after A→B
has already released A; B is the current field value, but no post-trap automatic
cleanup runs. Traps never unwind or roll back destruction.

A legally obtained concrete null Resource owner may initialize or replace a
field. Null needs no active flag and performs no release call. Null owned
containing objects perform neither deinit nor field cleanup.

## Containing-object ownership

Moving the class owner transfers eventual destruction responsibility transitively.
It does not move the individual handles or copy/relocate ObjectStorage. Fresh
OBJ-RET construction initializes fields in the existing final candidate storage;
forwarding preserves the same object pointer and field contents. Existing
Ownable dispose, relay and recursive forwarding continue to work. Only the final
owner destroys the object and its current fields.

There is no heap, reference count, object ownership header, active bitmap,
destructor pointer, generic callback, or runtime ownership table. Native PTR and
result-storage boundaries are unchanged. CABI does not gain class-layout support.
Owned ClassType fields await a storage-provenance solution; owned struct fields
await aggregate Move. See [ADR 0064](../decisions/0064-owned-resource-fields.md).
