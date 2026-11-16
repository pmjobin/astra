# astra-api-docs/1

The root contains `format: "astra-api-docs/1"`, `schema_version: 1`, compiler, build and
provenance labels, `inputs` and `symbols`. Input records contain a normalized
source-root-relative `path` and SHA-256 of the actual retained source bytes.
UTF-8 is preserved rather than Unicode-normalized. JSON has a fixed key order,
UTF-8 encoding and one final LF. Source-set ordering and symbol-ID ordering are
deterministic across fresh processes.

Every symbol has `id`, `canonical_name`, `kind`, `visibility`, `source_location`,
`owner`, `signature`, `type_contract`, `throws`, `parameters`, `type_parameters`, `generic_constraints`,
`attributes`, `availability`, `documentation` and `links`. Locations use UTF-8
byte offsets `[start,end)`. Documentation includes the Markdown body and its
original comment extent. No source body, arena ordinal, pointer or host path is
a public identity. IDs combine schema version, authenticated source profile,
Binder canonical name, kind and resolved signature; collisions are refused.
`owner` is null or the stable ID of the actual enclosing Binder declaration.
It provides navigation and breadcrumbs without interpreting names as source.
Function-local constants and other implementation locals are excluded in both
public and internal mode. Visibility includes the enclosing declarations.

`build.fingerprint` identifies the actual compiler source/toolchain material
recorded by `tools/docs/build.py`, separately from each executable's SHA-256.
The paired CLI link step in `tools/docs/link.py` also binds its link recipe and
launcher/guard sources into that material before rebuilding the private metadata
provider. The executed native Astra object remains byte-exact.
O0/O2 products from that material share this fingerprint. An unconfigured build
reports `unavailable`; it does not invent a compiler identity. Actual executable,
object, source and tool hashes remain in the authenticated build receipt.

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

Qualifiers are contextual. Callable declaration flags qualify its result and
declaration; the first recursive argument records the result channel directly.
A borrowed parameter has a call-scoped noescape contract. A borrowed stored
field is a readonly view bounded by its enclosing owning object, identified by
`owner`; its owning-sibling initialization and liveness need the separate native
source-owner proof. The `borrowed_noescape` label does not establish either proof.
Concrete nominal generic arguments and their names come from validated generic
instance plans, since diagnostic nominal rows alone omit those arguments.

`availability.profile` is the existing per-source profile (0 legacy27a, 1
astra27b). Qualification explicitly describes checked semantics; native lowering,
physical ABI and source/owner liveness remain separate verification boundaries.
Consumers must reject unknown schema versions, and must escape all source text.
The renderer supports a bounded safe Markdown subset. A future Astro/Starlight
adapter can consume this JSON without reparsing Astra or changing its semantics.

The machine schema is [schema.json](schema.json). Current native validation
results and remaining limitations are recorded in the engineering findings;
prose and a valid schema alone are not a conformance claim.
