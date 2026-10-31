# MODULE-1A: explicit source namespaces

Status: implemented in the compiler-systems campaign; qualification is recorded
in the campaign validation report.

The existing explicit multi-file compilation remains one program. A file may opt
into a single file-scoped `namespace Name;`. `using Name;` directives precede all
declarations and select short names from explicitly supplied sources. Namespace
names are single identifiers in this version. No path search, source loading,
remote dependency discovery, source mutation or runtime initializer is added.
Cyclic using directives are supported: declarations are collected before bodies.
Constant dependency cycles retain their existing rejection.

Namespaced declarations are public by default; contextual `public` documents that
choice. Contextual `internal` restricts a top-level declaration name to the same
exact namespace. It does not grant access to another Class's lexical private
fields. Existing global declarations and the global executable `main` policy
retain their behavior. Module visibility is name access control, not an opaque
binary interface or a promise that inferred types cannot cross public helpers.

Semantic declaration keys include namespace identity. Uses resolve in the current
namespace, then explicit imports (ambiguity is an error), then the existing global
scope. Builtin types and lexical bindings keep their existing precedence. Fully
qualified names bypass imports, never internal access checks. Qualified type
names, generic type applications, heap construction, free functions and constants
are supported. Import an enum type before using its variant/member syntax; nested
namespace chains and arbitrary chained static member expressions are deferred.

Core/CFG/SSA and native plans retain the exact checked identities. LLVM's existing
internal ordinal symbols already distinguish declarations; no public native ABI
is inferred. Global C symbols remain unchanged. New namespace C exports use an
injective length-prefixed encoding: `Left.identity` becomes
`astra_ns_4_Left_8_identity`. Imports preserve their short physical C spelling or
explicit `CCode(cname=...)`. Duplicate physical C symbols still reject before
LLVM output; imports never imply C symbol reach or alias compatibility.

This is whole-program source organization. Object-only emission can expose
explicit C exports to a host linker. There is no independently compiled Astra
module interface, package manager, partial declaration merge or stable ordinal ABI.
