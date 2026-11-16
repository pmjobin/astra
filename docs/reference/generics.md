# Generics and constraints

R-GENERICS. A generic declaration retains lexical type parameters, ordered
arguments and constraints. A concrete use must establish a checked specialization
with the exact nominal declaration and argument channels. Explicit type arguments
and supported inference are alternatives for selecting that concrete instance;
inference does not erase exact type or ownership requirements. The Guide's
`identity<int>` call supplies an explicit argument and a named value parameter.

Generic syntax accepts more than every downstream native body can emit. The
current source has separate generic syntax, instance-plan and specialization
verification, followed by ordinary owner/Flow/Core/SSA admission. A template
passing definition-time checks is not evidence that every concrete substitution
is native. Errors such as “generic body syntax lacks a concrete specialization
contract” must remain unsupported bounds, not be interpreted as permission to
weaken later verification.

R-CONSTRAINTS. `where` subjects bind lexical type parameters. Capability names
select checked, finite operations; they are not arbitrary reflection, runtime
duck typing or an unrestricted operator-overloading system. Copy transport,
owning transport and borrowed transport remain separate. A plain `T` cannot
launder an owning enum/Class/buffer into a copy channel. General constrained
class iteration has explicit negative controls in the range suite.

Closed generic classes used by the compiler, including checked owner-slot
collections, require their actual definition and concrete method contracts.
Changing a source-level type spelling is insufficient to justify field offsets,
receiver identity or ownership. Source-owner consumers and native physical
verification independently check the chosen specialization and its use.

## Resource ceilings

R-GENERIC-LIMIT. The instance ceiling remains 256. Generic syntax/symbol
expansion has bounded work and storage; SSA work remains at most 8,000,000.
These are implementation refusal limits, not a language promise of arbitrary
program size. The compiler must refuse safely when a budget is exhausted.
The books do not raise limits or bypass verification to accommodate an example.

For practical APIs, start with a small concrete value function, then generalize
only the operations your contract needs. Qualify actual instantiations at O0/O2
and include a rejected incompatible substitution. Generalized const generics,
higher-kinded polymorphism, automatic generic foreign interfaces and an open
monomorphization ABI are unproven in this edition. Source instance IDs and
generated specialization names are implementation details rather than portable
serialized type identities.

## Concrete capability rules

R-CAPABILITY-SET. The current checked capability set is finite:

| Capability | Concrete admission |
| --- | --- |
| Numeric, Ordered | Exact scalar numeric kinds |
| Eq | Numeric, bool or the admitted opaque pointer kind |
| Bitwise, Shift | Exact integer kinds |
| Ownable | Concrete class kind, with separate transport/flow proof |
| ExactHeapClass | Independently proved exact heap-class storage |

A name outside this set cannot establish arbitrary user-defined operations.
Every declared capability must hold for the concrete argument. The subject is
a lexical type parameter of the original declaration, not a type chosen by
matching a convenient spelling. The
[independent constraint consumer](../../compiler/semantic/generic-check.astra)
reconstructs those declaration/argument edges.

The Guide's [constrained addition](../guide/generics-match.md#constraints-at-concrete-calls)
instantiates both u8 and int. The same template refuses bool:

```astra example=negative-generic-capability
language astra27b;
T add<T>(T first, T last) where T: Numeric { return first + last; }
int main() {
	bool result = add<bool>(true, false);
	return 42;
}
```

R-SPECIALIZATION. A concrete instance retains its original declaration,
enclosing specialization and exact argument channels. Repeated equivalent
requests reuse that identity; distinct arguments/declarations consume distinct
instance obligations. The checked copier retains original tokens/spans and
reconstructs copied syntax, binding and scope edges. Source identity is separate
from target layout and native ABI proof.

Explicit owned record parameters remain refused by the current C0-compatible
source admission except for the designated generic record transport channels.
A copied specialization can remove a symbolic owning channel only when that
actual record is copyable. This is a constrained specialization rule, not
permission to erase ownership for arbitrary T. Owning-record generic capability
policies, open foreign generic ABIs and arbitrary native template bodies remain
separate limitations. The 256 instance and 8,000,000 SSA ceilings remain unchanged.
