# Concrete indexed heap-Class owners

The general checked-body `Vector<T>` profile also supports exact Resources and
copyable and owning record values. See [Resource storage](../decisions/0142-exact-resource-generic-storage.md)
and [record storage](../decisions/0143-copyable-record-generic-storage.md).
The original concrete heap-Class profile below retains its contract.

Q20A adds explicit growing storage for one exact nonpolymorphic heap Class.
The [diagnostic example](../../examples/diagnostic-slots/main.astra) stores
Diagnostics containing independently validated UTF-8 messages. Build and run it
with the hosted libraries selected explicitly:

```sh
build="$HOME/Workspace/codex/work/astra/build"
cc -std=c11 -Wall -Wextra -Werror -c lib/astra/platform/args-posix.c -o "$build/slots-args.o"
cc -std=c11 -Wall -Wextra -Werror -c lib/astra/platform/text-posix.c -o "$build/slots-text.o"
"$build/astrac" examples/diagnostic-slots/main.astra \
  lib/astra/text/utf8-message.astra lib/astra/base/errors.astra \
  lib/astra/hosted/text.astra --link-object "$build/slots-args.o" \
  --link-object "$build/slots-text.o" -o "$build/diagnostic-slots"
"$build/diagnostic-slots"
```

The default run renders three messages, then prints `drop diagnostics`, `drop 3`,
`drop 2`, `drop 1`. Arguments `empty`, `one`, `two` and `early` exercise shorter
lifetimes. The default path reserves two slots, appends two distinct owners,
reserves three slots, then appends a third. Count and object identity survive
that actual allocation change.

```astra
class Entries {
	owned Entry[slots] items;
	init() { this.items = new Entry[slots]; }
	bool reserve(int requested) { return this.items.reserve(requested); }
	void append(owned Entry entry) { this.items.append(move entry); }
	int count() { return len(this.items); }
	int capacity() { return this.items.capacity; }
	bool inspect(int index) { return inspect_entry(this.items[index]); }
}
// A concrete synchronous nonthrowing native free function:
// bool inspect_entry(Entry entry) { return entry.code == 42; }
```

`[slots]` is contextual for a Class field. Ordinary numeric arrays, numeric
buffer allocation counts named `slots`, slices and their existing ownership
rules retain their meanings. `new Entry[2]` remains unsupported.

A collection can declare one owned slots field and must initialize it exactly
once in its constructor. Empty initialization allocates nothing. Each append
requires an independently allocated, uniquely owned, exact heap Class; forwarding
parameters inherit that heap requirement. Lexical/caller-backed objects,
polymorphic elements and nested slots elements are excluded. A qualified T in
the separately bounded [generic Class bag](generic-class-bags.md) specializes to
this exact concrete field contract; unresolved generic elements elsewhere remain
excluded. Elements may own ordinary acyclic child fields and immutable text
snapshots.

| Operation | Result and ownership |
| --- | --- |
| `len(items)` / `items.capacity` | Readonly `int` values; no owner transfer. |
| `items.reserve(n)` | `false` for negative or unrepresentable capacity, with no mutation. `true` without allocation when current capacity suffices; otherwise grow to exactly n. Never shrink. |
| `items.append(move entry)` | Requires nonnull entry and `len < capacity`. Consumes one owner, increments count once and empties the source. Capacity is reserved separately. |
| `inspect_entry(items[index])` | Bounds-checked immediate borrow; helper must be a synchronous nonthrowing concrete native free function with scalar/void result and an exact borrowed Class parameter. |

Index and append precondition violations trap. They do not return a consuming
`false` or checked exception. The primitive checks before its transfer; an
ordinary wrapper has already acquired its owned parameter at the call boundary.
Fatal allocator exhaustion also traps. Neither fatal case promises unwinding
or a recoverable state. Normal negative-capacity rejection preserves the bag.
On the qualified hosted GNU x86-64 LP64 target, every nonnegative `int` capacity
is representable; requests near INT32_MAX are not tested by allocating them.

A borrowed element cannot become a local alias, return value, owned value,
method receiver or persistent view. Inspection can read metadata, compare
pointers and pass an ordinary child field to another synchronous reader. The
containing bag or a potentially aliasing ancestor cannot be another argument,
be consumed, or be mutated between index capture and the inspection call.
Nested argument calls obey the same exclusion. There is no purity inference.

Reserve moves pointer carriers and clears old carriers. It never relocates,
copies or destroys the Class objects or their message payloads. The bag's user
`deinit` runs first; automatic field cleanup then retires occupied elements in
reverse insertion order, including their child fields, before freeing backing
storage. Empty, early-return and ordinary checked-error paths share this rule.

The field is an indivisible `{PTR,I32,I32}` descriptor, 16 bytes aligned to 8
with offsets 0/8/12; each backing slot is an 8-byte pointer on the qualified
target. Private `owner-slots-v15` support is emitted only for programs using
slots fields. The descriptor has no standalone value, copy, extraction,
replacement, raw address, generic or C ABI channel. Bounds and capacity are
checked; cleanup and heap/borrow authority are verified through each compiler
stage and bound to the actual emitted LLVM operations.

See [ADR 0100](../decisions/0100-indexed-heap-owner-slots.md) for the approved
proof and validation for executed evidence.
General containers, iterators, removal and persistent borrowing remain future
work. Q11F/Q20B adds only the finite generic bag's direct operation patterns.


General templates derive record storage from the complete field graph. Owning
records use explicit named moves for insertion/replacement, complete take
results and exact per-field cleanup. Growth moves every physical channel without
retiring the elements. Copied records retain their indexed/foreach snapshot
behavior; those operations refuse to copy owning records. See
[ADR 0146](../decisions/0146-owning-record-container-elements.md) and the
[mixed-owner witness](../../tests/language-generalization-10/generic-owning-record.astra).
After take, the record uses the existing explicit field-take/replacement rules;
persistent owner-field borrows remain outside that profile.
