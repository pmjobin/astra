# Native parameter borrowing

Eligible [record slices](struct-elements.md) use the same mutable bounded native parameter borrowing rules. A complete COPY_VALUE record argument consumes its snapshot before later arguments, so a later owned-array transfer can be valid. A slice borrow or indexed receiver with a live address still cannot overlap transfer/replacement.

[Caller file/expression parameters](caller-information.md) are ordinary exact
BORROWED_NOESCAPE strings, even when omission supplies static literals. They
cannot escape through STATIC_TEXT results, acquire ownership or strengthen a
callee's contract according to a particular caller. Explicit forwarding has the
same lifetime obligations as other borrowed arguments.

ARGS-1 extends the same native borrowing default to `string[]`, including methods and constructors. It additionally promises stable descriptor and payload backing. The read-only table contract is separate from string-byte immutability; numeric slice permissions are unchanged. See [process arguments](process-arguments.md).

Ordinary bounded use uses ordinary parameters. Ownership-taking APIs visibly
use `owned`, and named transfers visibly use `move`.

```astra
void inspect(Resource resource) { /* borrows */ }
void draw(Renderer renderer) { renderer.draw(); }
void process(f64[] samples) { /* borrows */ }

void consume(owned Resource resource) { /* receives responsibility */ }
void install(owned Renderer renderer) { /* receives responsibility */ }
void take(owned f64[] samples) { /* receives responsibility */ }
```

Resource denotes an imported nominal handle, not a new native declaration form.
`var resource = open_resource(); inspect(resource); inspect(resource);` keeps
one owner live through both calls and eventually cleans it once. Class owned
results and buffer allocations work identically with their existing cleanup.
`consume(move resource)` transfers the named owner's responsibility explicitly.

| Native parameter | Contract |
| --- | --- |
| `bool`, integers, `f32`, `f64` | Ordinary value |
| Numeric vectors and masks | Ordinary value |
| Copyable concrete structs | COPY_VALUE, independent read-only parameter storage |
| Resource/HandleType | BORROWED_NOESCAPE |
| ClassType | BORROWED_NOESCAPE |
| SliceType `T[]` | BORROWED_NOESCAPE, as before |
| `borrowed` Resource/Class/Slice | The same BORROWED_NOESCAPE |
| `owned` Resource/Class/Slice | OWNED_TRANSFER, including owned-buffer transfer |
| `void*` | Existing unmanaged raw-pointer value |
| Supported typed pointers | Existing exact lexical pointer borrow rules |
| Generic `T` | Existing GEN-1/GEN-OWN policy; no inferred generic borrow |

These rules cover free functions, methods and constructors. Parameter names have
no special status. Native static methods remain unsupported. `this` keeps its
existing receiver contract, including nonnull authority; explicit Class
parameters remain nullable. Fields, results and property value domains do not
inherit parameter defaults. `var` remains local-only.

## Lifetime and mutation

Borrowing keeps the exact Resource handle, ObjectStorage pointer, or slice
base/length. The callee acquires no cleanup or ownership and performs no implicit
retain/release, ref/unref, copy, move or allocation. Resource and Class null
arguments retain the explicit borrow policy. Empty slices retain their existing
length/null-base behavior. Dereferencing a null object still traps normally.

Borrowed Class aliases may mutate the object and observe each other's changes.
Resource operations declared borrowed by their foreign contract may mutate it.
Slice element mutation remains visible to the caller. There is no readonly,
noalias or exclusive mutable borrow implication.

```astra
void inner(Renderer renderer) { renderer.draw(); }
void outer(Renderer renderer) {
	inner(renderer);
	renderer.draw();
}
```

Borrowing uses the existing domain-specific noescape rules. Resource parameters
cannot be captured into ordinary locals, stored or returned; they may compare
and forward directly to another borrowing parameter. Class and Slice parameters
retain their existing bounded local alias rules. Omitting `borrowed` never
extends a lifetime or enables fields, borrowed returns or persistent capture.

An owning field requires owning input, for example
`init(owned Resource resource) { this.resource = move resource; }`.
`init(Resource resource)` only borrows and cannot initialize that owned field.
The same rule applies to owned buffer fields. Class reference fields remain
unsupported; this milestone does not add owned Class fields.

## Overlapping ownership changes

The borrow stays live through the invocation, including later argument
evaluation. These same-owner calls reject for Resource, Class and buffer domains:

```astra
void inspect_and_consume(Renderer view, owned Renderer owner) {}
// inspect_and_consume(renderer, move renderer); // rejected
```

A nested later argument consuming the source also rejects. Existing conservative
provenance may reject potentially aliasing borrowed Class inputs and incoming
Class owners even when a caller knows they differ. An owned-field view cannot
overlap a potentially aliasing containing-object operation that could replace
its contents. No runtime pointer test is inserted.

Two borrows, `compare(renderer, renderer)`, may alias. A completed borrow no
longer overlaps a later transfer: `draw(renderer); install(move renderer);` is
legal. Resource/buffer release and replacement after a completed borrow remain
legal where their existing ownership contracts permit them. Class release,
replacement and local owner-to-owner moves are not expanded here. Argument
evaluation remains left-to-right.

## Compatibility and boundaries

PARAM-BORROW-1 intentionally changes plain native Resource parameters from
UNMANAGED to bounded borrows. The formerly valid
`Resource identity(Resource r) { return r; }` now rejects because its input is
borrowed. Resource result semantics themselves are unchanged. No unmanaged
Resource parameter keyword is added. The formerly accepted Class same-owner
borrow-plus-transfer call is also intentionally rejected.

Explicit `borrowed` remains useful for documentation and generated APIs. It
canonicalizes to the same Checked/Core contract as the plain spelling; no
overload or ABI distinction follows from the token. Overloading itself remains
unsupported. Semantic dumps expose `(contract borrowed-noescape)` for both.

C imports, exports, VAPI metadata, raw pointers and generic ownership keep their
existing rules. In particular, `T x where T : Ownable` and `borrowed T` remain
rejected; `owned T` still requires Ownable. Concrete native Resource/Class
parameters in generic functions use the ordinary concrete defaults.

See [ADR 0068](../decisions/0068-default-parameter-borrowing.md),
[Resource handles](resource-handles.md), [object borrowing](borrowed-object-parameters.md),
[slices](slices.md) and qualification.

## TEXT-1 immutable views

Plain `string` and explicit `borrowed string` native parameters are bounded
BORROWED_NOESCAPE views with immutable contents. Bindings retain the existing
parameter immutability policy. Aliasing, local descriptor copies and nested
reborrows are legal without cleanup or lifetime extension. Static string results
need independent definition-level backing proof. Resource/Class/buffer stored
borrowing and ownership rules remain unchanged. See [text](text.md).

GEN-SLICE-1 admits [generic borrowed slice algorithms](generic-slices.md): direct
function T[] formals derive exact mutable element-storage premises. Collections
remain borrowed while plain T parameters/results retain independent value copying.
No concrete element domain or ownership/lifetime rule is enlarged.
