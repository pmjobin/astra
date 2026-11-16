# astra-api-docs/1

The root contains `format: "astra-api-docs/1"`, `schema_version: 1`, compiler and
provenance labels, `inputs` and `symbols`. Input records contain a normalized
source-root-relative `path` and SHA-256 of the actual retained source bytes.
UTF-8 is preserved rather than Unicode-normalized. JSON has a fixed key order,
UTF-8 encoding and one final LF. Source-set ordering and symbol-ID ordering are
deterministic across fresh processes.

Every symbol has `id`, `canonical_name`, `kind`, `visibility`, `source_location`,
`signature`, `type_contract`, `throws`, `parameters`, `type_parameters`, `generic_constraints`,
`attributes`, `availability`, `documentation` and `links`. Locations use UTF-8
byte offsets `[start,end)`. Documentation includes the Markdown body and its
original comment extent. No source body, arena ordinal, pointer or host path is
a public identity. IDs combine schema version, authenticated source profile,
Binder canonical name, kind and resolved signature; collisions are refused.

Type contracts use resolved names, type-constructor kind, effective qualifier
flags, ownership designation, shared/weak policy, extent and recursive type
arguments. Flags preserve the current checked contract: nonnull=1, borrowed=2,
owned=4; additional declaration flags retain their compiler meaning. Callable
type arguments start with the result and then parameters. Generic parameter
names come from Binder declarations; generic constraints are checked capability
names associated with their actual owner-bound type parameters. `throws` is null
for no resolved error, including template declarations resolved through type uses.
Foreign import/export and concurrency metadata come from syntax checked by the
semantic model. `attributes.foreign_contract` uses the compiler's checked scalar,
UTF-8/i32 or counted-buffer/i32 ABI predicates; their noescape assertion does not
qualify a foreign implementation. Unsupported foreign profiles remain unproven.
An unresolved type has `status: "unproven"`; it is never
presented as a checked safety guarantee.

`availability.profile` is the existing per-source profile (0 legacy27a, 1
astra27b). Qualification explicitly describes checked semantics; native lowering,
physical ABI and source/owner liveness remain separate verification boundaries.
Consumers must reject unknown schema versions, and must escape all source text.
The renderer supports a bounded safe Markdown subset. A future Astro/Starlight
adapter can consume this JSON without reparsing Astra or changing its semantics.

The machine schema is [schema.json](schema.json). Current native validation
results and remaining limitations are recorded in the engineering findings;
prose and a valid schema alone are not a conformance claim.
