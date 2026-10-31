# Lexically stored borrows

A `Pair*` may hold the address of an initialized local Pair while that local's
storage remains live. DPTR-1 applies the same rules to supported integer/f32
T*. They are nullable and non-owning. Copies and destruction of the pointer do
not retain, free, or otherwise own the pointee.

```astra
struct Pair { int x; int y; }

int main() {
	Pair pair = { x = 1, y = 2 };
	Pair* p = &pair;
	Pair* q = p;
	q->x = 42;
	if (pair.x != 42 || p->x != 42) { return 1; }
	return 0;
}
```

Both pointers alias the same mutable storage, including direct `pair.x` accesses.
BORROW-1 enforces lifetime safety, not alias exclusivity. An explicit null guard
such as `p != null && p->ready` retains normal short-circuit behavior; evaluating
an indirect field access on null traps.

## Regions and outlives

Each checked lexical block has one exact compiler-owned LexicalRegion. The
function body is its invocation root. Nested if/else and while bodies form a
parent-linked tree. Region identity is independent of source positions or nesting
depth; function-local source-preorder ordinals are debug labels only.

A source region outlives a destination when it is the same region or a lexical
ancestor. Each pointer local requires every value assigned to it to remain valid
for that pointer's entire lexical storage region. The compiler checks exact
TypedPointerType identity and this outlives relationship at both initialization and
later assignment.

```astra
Pair* p = null;
Pair pair = { x = 1, y = 2 };
p = &pair;
if (condition) {
	Pair* q = p;
	q->x = 42;
}
```

The late assignment is valid: both p and pair end at the same boundary. The
pointee need not be declared before the pointer. It must already be visible,
which requires its complete initializer to have finished. A pointer declared in
a nested block can also directly borrow an enclosing local. A pointer may also borrow a struct
declared in the same nested block.

This program is rejected at `&inner`:

```astra
Pair* escaped = null;
if (condition) {
	Pair inner = { x = 1, y = 2 };
	escaped = &inner;
}
```

The diagnostic is:

```text
borrow from 'inner' cannot be stored in pointer 'escaped' because 'inner' has a shorter lexical lifetime
```

The same rule rejects loop-body or nested-loop storage assigned into an enclosing
pointer. There is no exception for an unreachable branch or a pointer that is
apparently unused afterward. No unsafe program reaches Core construction.

## Expression provenance and conservative copies

| Checked typed-pointer expression | Guaranteed provenance |
| --- | --- |
| Literal `null` | No pointee-lifetime requirement |
| Native pointer parameter | Complete receiving function invocation region |
| Pointer-local reference | That pointer local's lexical region |
| `&pair` | pair's local storage region |

Null may initialize or replace any compatible pointer. Reading a pointer local
summarizes all its stored values by the lifetime guaranteed by that local. The
compiler does not follow the original pointee through each subsequent copy.

Consequently, this copy outward is conservatively rejected even though pair
itself is still live:

```astra
Pair pair = { x = 1, y = 2 };
Pair* outer = null;
if (condition) {
	Pair* inner = &pair;
	outer = inner;
}
```

`inner` guarantees only its own nested region. Writing `outer = &pair` inside
that block is valid because it directly proves pair's enclosing region. An
inner pointer initialized only from null still advertises its local region;
assigning literal `null` outward is valid.

## Calls, branches, and loops

Native parameters may initialize locals at the function root or in any nested
scope. They may be passed through transitive calls and bounded recursion:

```astra
void recurse(Pair* parameter, int n) {
	Pair* p = parameter;
	if (n > 0) {
		p->x = p->x + 1;
		recurse(p, n - 1);
	}
}
```

The originating caller's storage remains live while callees execute. Ordinary
parameter assignment remains unsupported. Calls impose no longer-lived pointer
storage requirement because current native parameters cannot escape.

A pointer may select either of two enclosing structs across branches, or merge
null with a borrow. It may retain or change that safe value through loop
backedges. Each individual store proves validity for the pointer's region, so
merges need no further lifetime inference. Body-local structs and pointers can
borrow within each iteration; continue and break end their shared dynamic
scope. An inner-loop pointer may safely borrow an outer struct.

## Address expressions and limits

`&pair` is now a general typed-pointer expression: safe pointer initialization,
assignment, `&pair == p`, `&pair != null`, `consume(&pair)`, and `consume((&pair))`
are permitted. An exact visible, initialized native struct or supported
integer/f32 local may be addressed. Address-of bool/resource/vector/pointer
locals, direct/indirect fields, dereferences, parameters, and temporaries,
including `&(expression)`, remains unsupported.

Typed-pointer returns and struct fields remain prohibited. C imports/exports and
VAPI still support only void* pointer syntax, and T* has no conversion to void*.
There are no global/captured borrow destinations or pointer casts. These limits
close every current escape route beyond the active native call/lifetime graph.

Borrow semantics add no ownership, refcounting, heap allocation, destructor, mutability
qualifier, exclusive borrow, general reference type, or pointer arithmetic.
Future escaping references need explicit lifetime contracts.

Taking an address keeps a scalar local or an aggregate's fields in memory for
the whole checked function. Untouched locals remain promotable. Pointer locals
themselves remain scalar SSA values, including ordinary pointer phis. Borrow
checking ends before Core: immutable origin/region ordinal snapshots remain on
source addresses and dereference Places without keeping checked regions alive.
No runtime lifetime checks, borrow counters, retain/release, or extra
pointer-local alloca reaches execution. See [typed data pointers](typed-data-pointers.md)
and [dereference Places](../ir/dereference-places.md).

See [typed pointers](typed-struct-pointers.md),
[ADR 0027](../decisions/0027-lexical-borrow-regions.md), and
qualification.

## Ownership is separate

OWN-1 reuses each checked LexicalRegion to identify an owned foreign local's
scope. CoreBlock normalizes that scope for cleanup insertion; the Struct* borrow
proof itself still ends before Core. `owned void*` responsibility neither implies
borrow provenance nor changes native addressability/aliasing. A function may use
both independently. Calling a function with an owner requires explicit borrowed
parameter/noescape contracts. See [ownership](ownership.md).

MOVE-1 adds explicit responsibility transfer only between owned void* locals.
The ownership lattice runs over reachable CFG; Struct* borrow lifetime analysis
still runs over checked regions. Moving a handle neither changes a Pair* borrow's
provenance nor the addressable Pair's lifetime. Programs may combine stored Pair*
borrows, ordered memory accesses, owner null comparisons and moves. OBORROW-1 adds the separate [borrowed void* parameter contract](borrowed-parameters.md).
It allows temporary owner access through calls without copying ownership, changing
Struct* regions, or creating raw void* borrow provenance. `borrowed Pair*` rejects
to keep these systems distinct. Borrowed parameter aliases cannot enter storage.
