# Language profiles and source programs

R-PROFILE. A compilation explicitly receives all files forming one source
program. No automatic package search is implied by a namespace or import.
Each source can begin with one `language astra27b;` directive. Absence of a
directive selects legacy behavior; `language legacy27a;` selects it explicitly.
Unknown profiles, duplicate directives and directives after declarations fail.
The directive precedes a namespace declaration.

Profile selection belongs to each source and is independently verified against
original bytes. It is not a global textual rewrite. Explicit library files may
use their own established profile. Preserve those bytes rather than injecting
headers into imported sources.

Modern syntax includes hexadecimal/binary integers, selected trailing commas,
expression function/property bodies, record expressions, conditionals, compound
assignment, named arguments, expression matches, ranges, lazy transformations
and interpolation. Each still requires separate type, ownership and native
admission. Legacy source does not acquire modern syntax from its caller.

R-LEGACY. Modern ordinary shared parameters borrow, whereas legacy shared
spellings can elaborate implicit consuming parameters. Modern class defaults
are contextual: a bare native class parameter borrows, while an acquiring local
initialized by construction owns its object. The checked type's effective flags
settle the contract. An explicit owned factory result and `return move local`
make responsibility legible without guessing from a signature's surface text.

## A concrete profile refusal

This whole program is a negative fixture. It must fail compilation and preserve
an existing output sentinel; it is not an executable demonstration:

```astra example=negative-profile
language legacy27a;
int main() => 42;
```

Use a block-bodied function in legacy source or select the modern profile for
an expression body. Changing the header does not fix an ownership error or a
later native verification refusal. [Migration](../guide/tooling.md) describes
a review sequence that keeps those distinctions visible.

The native CLI has explicit checking, syntax dump, formatter, LLVM IR and object
modes. A development banner identifies a product family; qualification binds
exact source, tool and executable hashes. Neither the inherited `0.0.3` banner
nor the modern development banner announces a release or a supported installer.
