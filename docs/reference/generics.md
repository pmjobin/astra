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
