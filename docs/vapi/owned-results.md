# VAPI owned results (OWN-1)

RESOURCE-1 adds the primary nominal contract form:

```text
[CCode(destroy_function = "resource_destroy")] handle Resource;
owned Resource create_resource(int id);
```

The result's semantic type is Resource and its category is OWNED. Its exact
cleanup comes from Resource's HandleSymbol. Function-level destroy_function on
any handle result rejects; owned void* result syntax remains invalid. Once the
type is imported, `extern(C) owned Resource create_resource(int id);` supplies
an equivalent contract. Native owned results remain unsupported. The following
producer-specific void* metadata path is retained unchanged.
See [handle types](handle-types.md).

CCode accepts one new key, `destroy_function`, naming the exact external C symbol
that cleans a successfully returned void* resource:

```text
[CCode(
	cname = "resource_create_impl",
	cheader_filename = "resource.h",
	destroy_function = "resource_destroy_impl"
)]
void* create_resource(int id);
```

Astra uses `owned void* h = create_resource(1);`. The producer's local name,
producer's physical cname, and destroyer's physical name have separate meanings.
The destroyer is not looked up in the Astra callable namespace and need not be
separately declared to Astra. Source extern(C) has no equivalent metadata form.

## Grammar and validation

The existing metadata grammar is unchanged:

```text
metadata-attribute := "[" "CCode" "(" metadata-entry ("," metadata-entry)* ")" "]"
metadata-entry := identifier "=" string-literal
```

The complete key set is `cname`, `cheader_filename`, `destroy_function`. Keys may
appear once each in any order. destroy_function requires a nonempty decoded
string and exactly a void* result. int, void, bool, unsupported pointees, structs,
and deeper pointer results reject. Duplicate keys reject at the later key.
Non-string values, invalid escapes, and embedded NUL follow the existing VAPI
metadata diagnostics. Symbol spelling remains exact and opaque, including valid
punctuation; it is not restricted to Astra identifiers.

The physical cleanup signature is frozen at one PTR parameter and absent result:
`void cleanup(void* resource)`. There is no context/user-data argument. The
compiler supplies no inferred alias, retention, nullability, or unwind attributes.
Headers remain descriptive and unopened, so header contents never establish or
validate a cleanup signature. Implementation/linkage remains the binding author's
responsibility, supplied independently through `--link-object`.

## Normalized ownership contract

VapiNormalizer constructs immutable, syntax-independent generic metadata:

```text
CForeignMetadata.owned_result
	CForeignOwnedResultContract.cleanup
		CForeignCleanupContract.external_symbol
		CForeignCleanupContract.symbol_span
```

Semantic collection interns cleanup contracts by physical symbol across all
input files, in first declaration encounter order. Equal strings enter one
contract identity here; later consumers use exact identity maps. CFunctionSymbol
owns the normalized result contract after VAPI syntax/input destruction.
Checked calls retain OWNED(cleanup) independently of the canonical void* type.
All ordinary contexts reject the result; only the direct owned-local initializer
accepts acquisition. An unannotated void* result remains unmanaged.

Core copies descriptive metadata without the semantic ownership object and
builds its own cleanup identity. CFG, SSA, and CABI each build independent
identities before instruction mapping. No downstream stage retains VAPI nodes or
re-resolves destroy-function spellings during calls.

## C ABI identity

CAbiCleanupFunction is compiler-generated foreign cleanup authority, separate
from ordinary source imports. It owns the exact symbol, provenance, ordinal,
and `(PTR) -> void` signature under existing scalar-ptr-v1. Multiple producers
sharing a destroyer refer to one cleanup declaration. A cleanup symbol cannot
collide with an ordinary C import or export, even if a user thinks their
signatures are compatible. CABI validates cleanup declarations first, ordinary
imports next, then exports; the later physical claim supplies the diagnostic.
No LLVM auto-renaming is permitted.

```text
(c-abi scalar-ptr-v1
	(cleanup #0
		(symbol "resource_destroy_impl")
		(signature (parameters (parameter #0 PTR)) (result void)))
	(import #0
		(name "create_resource")
		(symbol "resource_create_impl")
		(owned-result (cleanup #0))
		(signature (parameters (parameter #0 I32)) (result PTR))))
```

A returned null still establishes an owner, whose cleanup skips the C call.
Non-returning factories establish no completed acquisition. Traps do not unwind.
See [source ownership](../language/ownership.md), [metadata v0](vapi-c-metadata-v0.md),
and [cleanup IR](../ir/cleanup.md).

## Borrowing an acquired owner

After `owned void* h = create_resource(1);`, a `borrowed void*` parameter may
receive `h` temporarily while it is definitely OWNED. The owner keeps its exact
destroy_function contract and lexical cleanup obligation. The actual pointer may
be null. `inspect(create_resource(1))` still rejects: responsibility must first
enter an owner. Cleanup's compiler-owned PTR parameter remains destructive and
UNMANAGED, separate from source borrowed contracts. See [borrowed parameters](borrowed-parameters.md).
