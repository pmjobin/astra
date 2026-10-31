# 0020: Explicit scalar C imports

Status: accepted for ASTRA-CABI-1.

C interoperability is an explicit foreign boundary. `extern(C)` declares an
externally implemented function; it never creates an Astra-native body. Native
functions retain Astra semantics, NABI scalar-v0, internal LLVM linkage, `fastcc`,
and backend-local `astra.fn.N` names. The C ABI governs transport across a call,
while Astra governs expression evaluation before and after that call.

The frozen decisions are:

1. Foreignness requires `extern(C)`. Ordinary definitions keep their bodies;
   an ordinary bodyless prototype is invalid. Foreign declarations require a
   semicolon and reject a body.
2. `extern` is a keyword. The ABI identifier is an ordinary identifier whose
   spelling must be exactly `C`; unsupported ABI names receive a semantic
   diagnostic. `C` remains usable as an ordinary identifier elsewhere.
3. `CFunctionSymbol` owns exact foreign identity, `ForeignAbi.C`, source and
   external names, semantic result/parameter types, parameter symbols, and
   declaration provenance. Compilation-unit authority strongly owns imports.
4. `DirectCallableSymbol` has explicit `CallableDomain.NATIVE` or `.C` and the
   concrete `FunctionSymbol` or `CFunctionSymbol`. One compilation-unit lookup
   resolves each checked call once, including calls preceding an extern.
5. Native and imported names occupy one unique direct-function namespace.
   Duplicate names reject regardless of domain or signature; no overloading.
6. Checked expression/statement calls retain exact weak callable references.
   Native functions and imports have separate owning arrays. Calls cannot
   create recursive ownership cycles. An imported `main` is not an entry.
7. Core, CFG, and SSA each own independent native and imported identities.
   Every declaration is created before native body translation. Temporary exact
   maps connect semantic → Core → CFG → SSA; names never re-resolve calls.
8. Distinct Core C call values/statements and CFG/SSA C call instructions expose
   the domain to verifiers. Imports have no body, blocks, or successor edges.
9. Initial foreign parameters are exactly semantic `int`; results are `int` or
   `void`. Arguments require exact semantic types and arity, with no conversion.
   Void is usable only as a statement. Int results may be deliberately discarded.
10. Foreign `int` is an exact signed 32-bit ABI channel, qualified using C
    `int32_t` from `<stdint.h>`. This does not permanently equate Astra `int`
    with source-level C `int` on every target.
11. Foreign bool is unsupported. Astra bool's true/false semantics and native
    B1 channel make no claim about C `_Bool` representation or ABI realization.
12. The declaration spelling is the exact external symbol in this milestone.
    No mangling, aliases, attributes, manual underscores, or platform decoration
    are added. LLVM/object tools realize platform object symbols.
13. Every imported call is conservatively effectful. Its scalar signature does
    not justify CSE, elimination, duplication, or reordering. Unused int results
    keep their call. Unreachable SSA projection remains ordinary reachability.
14. Astra's left-to-right operand/argument order applies. Both domains share
    ordered CFG argument construction, including evaluation before later
    effects. Short-circuit RHS paths, loop conditions, and transfers retain
    their existing control-flow semantics. Calls are never CFG successors.
15. NABI remains exclusively native. Its validator accepts native SSA call
    nodes only. C imports cannot enter its typed function maps.
16. `src/cabi/` independently owns foreign physical signature authority.
    `CAbiProfile.SCALAR_V0` versions Astra's interop subset, not the host C ABI.
    `CAbiScalarType.I32` is a separate identity from native I32. Void means no
    result; there are no hidden channels or semantic type objects in the sidecar.
17. CABI plans all foreign physical identities before validating call sites via
    exact temporary `SsaCFunction → CAbiFunction` maps. Ordinals preserve import
    declaration order. `CAbiProgram` retains no SSA or other upstream graph.
18. LLVM consumes verified SSA, NABI, and CABI. A separate CABI-to-LLVM mapper
    supplies external declaration signatures. Import declarations and calls use
    default C convention (`ccc`, omitted by LLVM's printer), with exact identity
    maps through CABI and no call-time module lookup by string.
19. LLVM's general verifier is supplemented by C import contract checks for
    exact name/type/target, external linkage, declaration-only status, and C
    convention. These records own only copied symbols and borrowed LLVM handles.
20. Symbol availability is checked at link time. `--check`, `--dump-cabi`, and
    `--dump-llvm` need no implementation object. `--link-object PATH` is repeatable
    for executable compilation and preserves user object order in shell-free
    linker argv. Link failure preserves existing output and cleans temporaries.
21. CABI model/verifier/dumper compile with shared provenance only; its builder
    and tests stay LLVM-free. Sidecar data never becomes semantic type authority.
22. Future VAPI-like declarations will produce the same semantic foreign model
    and boundary. They will enrich declaration input rather than introduce a
    second FFI system. No VAPI, header discovery, C exports, pointers, strings,
    aggregates, callbacks, variadics, C bool, ownership, GIR, or GObject is added.

The narrow representation choice is a common semantic lookup interface with an
explicit domain, followed by distinct C nodes in the existing IRs. A universal
ABI-bearing function object would blur native authority. A complete parallel
expression/control-flow pipeline would duplicate established semantics. Distinct
call nodes plus the shared ordered-argument routine preserve both boundaries
without redesigning NABI, SSA promotion, short-circuit lowering, or loop control.

See the [physical contract](../abi/c-scalar-import-v0.md),
[language rules](../language/c-interop.md), and
qualification report.
