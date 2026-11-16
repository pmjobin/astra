# Declarations and name resolution

R-NAMES. Explicit source files establish the input set. Namespace/import
directives name semantic scopes rather than locate packages on disk. Declaration
binding establishes nominal identities before expression checking. Qualified,
same-namespace and imported lookup respect visibility; types and values occupy
distinct lookup domains. Equal names in separate declarations do not become one
type because their storage shapes match.

Free headers precede body checking. Parameters, locals and members retain their
source owner and scope. An initializer is checked before its new local is
inserted, preventing accidental self-reference. Active local/parameter hiding
is restricted; sibling regions may reuse names after their lifetimes end.
Unknown, ambiguous, inaccessible and receiver-dependent references are distinct
outcomes. Deferral is not a fabricated successful binding.

R-LOCALS. A typed local supplies initializer context. `var` infers from an
admitted initializer; it does not disable ownership or lifetime checks.
Initialization completes before the local becomes live. Construction and owning
results establish cleanup responsibility; scalar and eligible record copying
create independent values. Those categories explain why record copying can be
valid while owner copying is refused.

Fields retain declaration, visibility and initialization obligations. `readonly`
restricts later writes rather than asserting a general borrow contract. An owning
field must receive its required initialization; a stored borrow requires a
longer-lived owner. See [Ownership](ownership.md) and [Sharing](shared.md).

## Constant boundary

R-CONSTANT-BOUNDARY. The frontend has constant declarations and extent-expression
support. Current native Flow refuses this representative top-level constant
use, so this edition provides no general native constant-expression guarantee:

```astra example=negative-constant
language astra27b;
const VALUE = 42;
int main() {
	return VALUE;
}
```

Use a typed local for the executable calculation in the [Guide](../guide/values.md).
That substitution is not a compiler repair or a change to constant semantics.
The refused form remains in the feature matrix with its failure stage. A later
implementation must receive its own conformance evidence before the bound can
be relaxed. The matrix also distinguishes source declarations from API metadata:
a documentation TypeId is not proof that native storage or execution is admitted.
