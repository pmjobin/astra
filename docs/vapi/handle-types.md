# VAPI handle types (RESOURCE-1)

```text
vapi-file := vapi-declaration* EOF
vapi-declaration := handle-declaration | function-declaration
handle-declaration := ccode-attribute "handle" identifier ";"
function-declaration := ccode-attribute? function-result identifier "(" parameters? ")" ";"
function-result := "owned"? type-syntax
parameters := parameter ("," parameter)*
parameter := "borrowed"? type-syntax identifier
type-syntax := identifier "*"*
ccode-attribute := "[" "CCode" "(" metadata-entry ("," metadata-entry)* ")" "]"
metadata-entry := identifier "=" string-literal
```

Extra pointer stars are retained for diagnostics; they do not enable handle
pointers or pointer depth. The existing comment, encoding, string-escape and
duplicate-key rules apply. There are no trailing commas, bodies or exports.
`handle` and `owned` are reserved VAPI keywords alongside `borrowed`.

| Handle metadata | Policy |
| --- | --- |
| `destroy_function` | Required nonempty exact C symbol, with fixed physical `void(void*)` signature |
| `cheader_filename` | Optional nonempty opaque header metadata |
| `cname` | Rejected; the semantic handle type has no C linker symbol |

Missing cleanup, empty values, duplicate keys and unknown keys reject. Headers
are never opened, preprocessed or validated and never infer a link input. A
nonexistent header does not affect checking, ABI/LLVM lowering or execution with
a supplied object. Binding authors supply a compatible C implementation.

```text
[CCode(destroy_function = "resource_destroy", cheader_filename = "missing/resource.h")]
handle Resource;
[CCode(cname = "resource_create")]
owned Resource create_resource(int id);
int inspect_resource(borrowed Resource r);
Resource lookup_resource(int id);
```

The owned-result qualifier is valid only for an exact imported handle type.
Its cleanup comes from that type's declaration. A function-level destroy_function
on a handle result rejects, including redundant metadata naming the same cleanup.
The older `[CCode(destroy_function = "destroy")] void* create();` path remains
unchanged; `owned void* create();` is not its replacement.

Unqualified handle parameters/results are unmanaged. Borrowed handle parameters
are trusted noescape contracts with the same semantics as source extern(C).
Once the type is loaded, `extern(C) owned Resource create_resource(int id);` and
`extern(C) int inspect_resource(borrowed Resource r);` normalize like their VAPI
equivalents apart from provenance. Native owned boundaries remain unsupported.

`VapiHandleDeclarationSyntax` owns the exact name/keyword/semicolon tokens,
metadata syntax and covering SourceSpan. `VapiFileSyntax` keeps ordered handle
and function arrays. These are independent of semantic, Core, CFG, SSA, ABI and
LLVM code. `normalize_handles` produces `ForeignHandleInput` containing copied
cleanup/header metadata and provenance; existing `normalize` produces function
inputs, now retaining an owned-result qualifier bit. Neither normalized input
contains semantic type identity.

The driver concatenates both arrays in CLI file order. Semantic analysis first
collects all handle identities, then collects source struct identities and fields,
then resolves foreign/source signatures and native bodies. The ordinary named
type table contains both handles and structs; builtins retain their canonical
universe. Collisions reject deterministically. Thus an API can reference a handle
declared in a later file. Handle ordinals use file order and handle declaration
order, never hash-table traversal or first use. Reordering only an API file and
its type file does not change semantic results or dumps.

`HandleSymbol` owns a canonical `HandleType`, one interned cleanup contract,
optional header, exact name/declaration spans and ordinal. Nominal identity is
object identity, independent of spelling, cleanup sharing or PTR representation.
The type token contains no upstream symbol/syntax/cleanup backlink. Each IR stage
owns a separate handle descriptor and cleanup authority, permitting preceding
stages to die. See [language rules](../language/resource-handles.md) and
[ADR 0033](../decisions/0033-nominal-resource-handles.md).
