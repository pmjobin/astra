# Declaration-derived C Class imports

This intermediate M16 implementation imports copied scalar members, scalar
reference channels, counted byte/text parameters, owned byte/UTF-8 results, copied
PODs, borrowed/consumed imported objects, owned object results and checked factories
from a matching C `declarations-v1` provider. A declaration has no implementation
fields or bodies:

```astra
[CImport(name="provider", profile="declarations-v1", lifetime="unique",
         threading="constructing", bool_abi="c99")]
class Provider {
	[Foreign(error_factory="foreign_fault", error_domain="16", errors="Fault=-1600")]
	init(int initial) throws Fault;
	[Foreign(error_factory="foreign_fault", error_domain="16", errors="Fault=-1600")]
	bool choose(bool input) throws Fault;
}
```

`Provider.init(...)` produces a unique native Resource owner of the exact opaque
provider handle. `owner.choose(...)` is an ordinary checked native call with an
implicit call-scoped handle borrow. The foreign name defaults to `create` for the
factory and the declared method name for a method. An explicit `Foreign(name=...)`
changes the foreign symbol while preserving its native declaration identity.

The prefix determines the matching public C status/out/error functions and owner
operations. A unique owner retires through the provider's consuming `destroy`
operation. `lifetime="shared"` retires one provider reference through `release`.
The native Resource remains linear in both cases; there is no added native RC,
proxy object or ownership inferred from pointer width. The provider retains its
declared constructing-thread and lifetime obligations. Provider-defined duplication
methods can return an additional owned reference. Consuming parameters use private
C owner slots with exact remaining-owner retirement. Weak handles remain subsequent work.

An explicit error factory is a nonthrowing native function returning an owned
heap instance of the declared exception bound, with two i32 parameters: domain
and status. Its actual native body constructs the exception. The compiler binds
that exact function through each stage; it does not infer constructor arguments
or implement application error behavior. A factory that returns null violates the declaration and traps before returning
an exception. Ordinary native allocation behavior remains unchanged.

The bridge uses private success/error storage. It publishes native results for
status zero, or a declared empty nullable-result status, with a cleared error
record. A declared negative status requires
a matching error code and either the declared domain/status map or infrastructure
domain zero. Contradictory records, undeclared positive statuses and a missing
mandatory owner become domain-zero `0x8000ffff` failures. A provisional C owner is
retired before constructing the native exception, including when a broken provider
returns an owner on failure. An explicit positive `null_status` succeeds only for
a nullable empty object result with a cleared error record.

The same immutable member/channel schema binds the nominal handle, source member
ordinal, foreign symbol, parameter/result types, owner cleanup and exception
factory. Core has one typed foreign-return operation; CFG/SSA retain that operation
as a terminal boundary. Each stage reconstructs its signature and requires exactly
one adapter for every declared member. Native and C ABI plans independently check
their respective representations. LLVM preserves exact C bool extensions and the
complete native conversion sequence. These adapters contain transport and cleanup
only; provider algorithms execute in the separately compiled C implementation.

The independent/generated-header provider matrix covers all seven copied scalar
kinds, void methods, unique/shared retirement, native catches, dirty provisional
owners, malformed status/error records and missing owners at O0/O1/O2. It includes
eight unsuppressed whole-executable Valgrind runs and nine source admission/ownership
negatives. Detached mutations remove or substitute member operations, error
factories, native plans, C bool channels and LLVM argument/extension facts. Weak
operations and callbacks
remain active implementation work. This slice does not complete M16.

The later [reference-channel slice](declaration-interop-16-c-import-references.md)
adds typed scalar pointer inputs/outputs with staged publication and rollback.
The [counted-parameter slice](declaration-interop-16-c-import-counted.md) adds byte
views and native UTF-8 string inputs with bounded mutable output publication.
The [owned-result slice](declaration-interop-16-c-import-owned.md) adds independent
native snapshots, UTF-8 validation and matching provider allocation retirement.
The [POD import slice](declaration-interop-16-c-import-records.md) adds nominal
scalar records and closed instances through reverse target-C ABI forwarding.
The [handle slice](declaration-interop-16-c-import-handles.md) adds nominal borrowed
objects, owned cross-root results and explicit nullable query statuses.
The [consuming slice](declaration-interop-16-c-import-consuming.md) adds explicit
native input duties and private C owner-slot retirement on every call path.
The [foreign-handle export slice](declaration-interop-16-foreign-handles.md) carries
these typed Resources through native Class exports and ordinary owned fields.
The [property slice](declaration-interop-16-c-import-properties.md) adds selected
typed getter/setter declarations with ordinary native property access syntax.
