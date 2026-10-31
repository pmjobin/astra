# Finite exact-Class generic bags

This page preserves the historical exact-Class/general-body component profiles.
For current declaration-derived storage, multiple parameters/fields, owning
members and native boundaries, use [structural generics](structural-generics.md).

Surge 10 also provides a separate general-body template profile without the
`where T : ExactHeapClass` clause. It checks ordinary control flow and member
calls after specialization; its current storage arguments include exact heap
Classes, Resources and copyable or owning records. See [ADR 0141](../decisions/0141-checked-generic-class-bodies.md),
[Resource storage ADR 0142](../decisions/0142-exact-resource-generic-storage.md) and
[record storage ADR 0143](../decisions/0143-copyable-record-generic-storage.md), plus
[the source witness](../../tests/language-generalization-10/generic-body.astra).
The general-body profile also supports explicit method applications such as
`values.echo<int>(7)` for `U echo<U>(U value)`. One copied closed U argument is
checked per application, independently of the Class T specialization. Record U
uses complete copied value groups; Class/Resource/owning-record T keeps its exact
move and destruction rules.
See [ADR 0144](../decisions/0144-explicit-generic-method-specialization.md) and
[the method witness](../../tests/language-generalization-10/generic-method.astra).
Owning record T uses explicit named whole-record moves and complete take results;
see [ADR 0146](../decisions/0146-owning-record-container-elements.md).
General applications can also cross concrete synchronous owned parameter/result
boundaries. Checked borrowed helpers can return values or extracted element
owners. [ADR 0147](../decisions/0147-general-generic-owner-boundaries.md) describes
argument rollback and the exact native owner channels. Nested/child applications
and async boundaries remain outside this component.
The finite profile described below retains its historical restrictions.

Q11F/Q20B permits the single reusable native Class declaration in
[collections/bag.astra](../../lib/astra/collections/bag.astra):

```astra
class Bag<T> where T : ExactHeapClass {
	owned T[slots] entries;
	init() { this.entries = new T[slots]; }
	bool reserve(int requested) { return this.entries.reserve(requested); }
	void append(owned T value) { this.entries.append(move value); }
	int count() { return len(this.entries); }
	int capacity() { return this.entries.capacity; }
	owned T take(int index) { var value = this.entries.take(index); return move value; }
	void replace(int index, owned T value) { this.entries.replace(index, move value); }
}
```

Select that source explicitly with the element Classes and your application.
`new Bag<Diagnostic>()` and `new Bag<Utf8Message>()` produce distinct ordinary
unique heap-Class owners. Repeated applications of the same definition and exact
argument coalesce. Two different definitions remain different even with identical
arguments and fields. Names, pointer widths and physical layouts do not establish
type compatibility. A named bag owner can move to another same-type named owner
without relocating its allocation or elements.

`ExactHeapClass` is contextual to this declaration's where clause. It adds no
global keyword, user trait or free-function capability. There must be one exact
type parameter, one owned T[slots] field, one complete empty initializer, and four
required direct methods with the reserve/append/count/capacity bodies shown.
Two optional finite recipes add take/replace; the public Bag supplies both. Declaration,
field, method and parameter names can differ. The five operation patterns are
checked even in unused declarations. Unbounded generic Classes and arbitrary
generic member bodies remain unsupported.

The argument must be a concrete native Class with no inheritance, polymorphism
or nested owner-slot storage, including through child fields. Scalars, immutable
UTF-8 snapshots and ordinary acyclic owned children retain their existing rules.
Resource, struct, unresolved/generic, foreign and generic-bag elements reject.
The bound does not turn lexical/caller-backed objects into heap owners. Every
append independently requires one live named exact heap owner and explicit move.
There is no generic `new T()` or partial field extraction. Element-owner take
is a separate exact operation described below.

Capacity and destruction use the existing [Q20A owner-slot contract](owner-slots.md):
empty initialization allocates nothing, reserve explicitly grows or preserves
capacity, and append never auto-reserves. A larger reserve moves and clears
pointer carriers, preserving object/snapshot addresses. Negative/unrepresentable
capacity returns false without mutation. Invalid dynamic indexing, null/full
append and allocator exhaustion trap without an unwind guarantee. Normal scope,
early return and qualified checked-error cleanup retire elements in reverse
current slot order, with exact child destruction, element free and one backing free.

## Concrete inspection

Element access is an immediate borrowed argument to an ordinary exact-Class
inspector. A concrete helper can select the bag's specialized field:

```astra
bool message_is(Utf8Message message, string expected) {
	var view = message.text;
	return view == expected && view.byte_length == expected.byte_length;
}
bool inspect_message(Bag<Utf8Message> bag, int index, string expected) {
	return message_is(bag.entries[index], expected);
}
```

The bag and element are borrowed only for concrete synchronous nonthrowing calls.
The message-bound text view stays inside `message_is`. Inspection returns copied
scalar/void results; it cannot return/store a borrowed element or persistent text
view. Capturing an indexed element excludes later mutation or consumption of the
same or possibly aliasing container, including nested argument evaluation. The
inspector cannot release or move its borrowed element. No callback or dynamic
member discovery is involved.

Generic method type parameters, extra fields, properties, user deinit, inheritance,
virtual/async/throwing template members and arbitrary template control flow remain
excluded. Bag results, owned bag helper parameters, child-field composition and
passing bags into unrelated generic free functions/records are also outside this
finite scope. Concrete borrowed helper parameters and same-type local owner moves
are supported. Existing ordinary Class/Resource, copyable generic structs,
generic free functions, arrays, buffers, slices and foreign ABI retain their
contracts. Q11 and Q20 remain open beyond this subset.

## Example and qualification

[The application](../../examples/generic-diagnostic-bags/main.astra) interleaves
the two specializations from one Bag declaration. Each holds two live elements
before reserve 2→3, then acquires a third. It checks counted NUL, composed and
combining UTF-8, independent identity, capacity and ordinary error cleanup.

From the repository root:

```sh
sh tests/gen-member-1a/verify.sh focused
build="$HOME/Workspace/codex/work/astra/build"
example_out="$build/examples/gen-member-1a"
mkdir -p "$example_out"
cc -std=c11 -Wall -Wextra -Werror -c lib/astra/platform/args-posix.c -o "$example_out/args.o"
cc -std=c11 -Wall -Wextra -Werror -c lib/astra/platform/text-posix.c -o "$example_out/text.o"
"$build/astrac" examples/generic-diagnostic-bags/main.astra \
  examples/generic-diagnostic-bags/model.astra lib/astra/collections/bag.astra \
  lib/astra/text/utf8-message.astra lib/astra/base/errors.astra \
  lib/astra/hosted/text.astra --link-object "$example_out/args.o" \
  --link-object "$example_out/text.o" -o "$example_out/generic-bags"
"$example_out/generic-bags"
```

Default stdout is `checked\ndrop 3\ndrop 2\ndrop 1\n`. Arguments `empty`, `one`,
`two`, `early`, and `error` exercise shorter or checked-error lifetimes.
Use `verify.sh regressions` for the selected compatibility fence.
The private owner-slots-v15 descriptor remains PTR/I32/I32, size 16, alignment
8, offsets 0/8/12 and pointer stride 8 on the qualified hosted GNU x86-64 LP64
target. Definition keys and borrowed-bag type provenance are compile-time
metadata; no runtime tag, vtable, refcount or ownership registry is added.
An unused generic declaration emits no owner-slot helper.

[ADR 0101](../decisions/0101-exact-class-generic-bag.md) records the user-approved
scope and proof; [the test README](../../tests/gen-member-1a/README.md) describes
the independent source/stage/native/LLVM evidence and preservation boundaries.

## Owner extraction and replacement

```astra
var taken = bag.take(1);             // one new owner, stable remaining order
var replacement = new Diagnostic(7, move message);
bag.replace(0, move replacement);    // install new owner, retire old owner
release taken;                      // independent lifetime
```

An invalid index (including empty take/replace) traps before changing the bag.
Take shifts later carriers left and clears the old last carrier; it preserves
capacity and object pointer identity. The only/last/first cases use the same
primitive. Replacement preserves count and capacity and installs the new pointer
before destroying and freeing the previous element. Checked producers must finish
before the consuming call. Existing fatal backing allocation remains unchanged.

Take enters one fresh named owner. There is no inline/discarded extraction or
persistent slot loan. Ordinary owner moves, checked-scope unwinding, release and
text-loan invalidation then apply to the extracted object. Inspection loans exclude
both new mutations, even if the object allocation itself would stay put. Raw
`owned T[slots]` fields of concrete Classes expose the same guarded primitives;
there is no source access to the movable pointer array itself.

[ADR 0117](../decisions/0117-exact-class-bag-owner-extraction.md) and
owned-state qualification retain the source,
stage and actual host limits. Q11/Q20 stay open beyond exact heap Classes.


Closed general-body containers may own other closed general-body containers.
For example, Vector<Vector<Packet>> transfers each inner container as an exact
heap owner. Inner copied or owning records keep their full value layouts and
cleanup responsibilities. Readonly nested count/capacity queries are allowed
within outer foreach loans; reserve/take/replacement and loan escape reject.
The older ExactHeapClass Bag profile keeps its historical restrictions.
See [ADR 0148](../decisions/0148-nested-generic-container-ownership.md).

General-body templates also support direct computed get-only `int` and `bool`
properties. For example, `property int size { get { return len(this.entries); } }`
observes the current specialization on every access. Properties may be interleaved
with constructors, ordinary methods and copied-U methods. Each specialization
retains its own typed receiver and immutable declared property schema through the
native target mapping. Template setters, lazy/throwing/virtual properties and
T-valued element projections remain outside this profile. The legacy constrained
Bag keeps its original property refusal. See
[ADR 0153](../decisions/0153-direct-properties-on-general-generic-classes.md).
