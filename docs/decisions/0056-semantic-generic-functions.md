# ADR 0056: Semantic generic functions

Status: accepted for ASTRA-GEN-1, based on accepted ASTRA-PROP-1
`07aeb36b4af337add8fd886992af8f6cb218047b`.

## Decision

1. Astra generics are semantic static abstractions, never textual templates.
2. Each generic definition is checked once, independently of its instances.
3. A generic definition owns ordered exact TypeParameterSymbols.
4. Type-parameter identity is lexical and compiler-owned.
5. A generic definition has no native ABI.
6. Only concrete instances have native ABIs.
7. A generic definition has no LLVM function.
8. Only concrete instances reach LLVM.
9. Concrete instances are demand-driven.
10. An instance key is exact definition identity plus ordered canonical concrete semantic type identities.
11. Instance identity does not depend on source spelling.
12. Instance identity does not depend on LLVM types.
13. Instance identity does not depend on NABI physical representation.
14. `int` and `i32` therefore select the same canonical instance.
15. `i8` and `u8` select distinct instances.
16. All same-representation semantic types remain distinct.
17. Instances deduplicate globally within one compilation, including all native callable kinds.
18. The monomorphizer registers a complete concrete signature placeholder before traversing its body.
19. Direct recursion reuses that in-progress instance.
20. Mutual generic recursion is supported by the same registry and worklist.
21. Generic bodies may call generic functions with explicit type arguments.
22. Those arguments may be current type parameters, in any explicit order, or eligible concrete types.
23. Instantiation never repeats source name/type resolution or generic body acceptance.
24. Operations unsupported by a type parameter reject during definition checking.
25. Successful concrete types never retroactively legalize an invalid definition, even if all calls use those types.
26. GEN-1 type parameters have the bounded `GEN1_PLAIN_COPY` capability.
27. Concrete arguments are restricted to lifetime-neutral ordinary copy values.
28. User capability syntax is deferred to GEN-CAP-1.
29. GEN-1 does not infer type arguments.
30. Every generic call supplies the full ordered type-argument list; no defaults or partial inference exist.
31. Parameters and results may use a type parameter directly.
32. Locals may use a type parameter directly.
33. A type parameter cannot occur inside another type constructor.
34. Generic ownership is deferred, including `owned T` and `borrowed T`.
35. Generic members, generic structs and generic classes are deferred.
36. Generic C/VAPI declarations and boundaries are unsupported.
37. Concrete instances select existing NABI channels and profiles after substitution.
38. Concrete instances use existing LLVM lowering after substitution.
39. No runtime type metadata is introduced.
40. No boxing is introduced.
41. No runtime generic dispatch, dictionaries or witnesses are introduced.
42. Future generic structs and interfaces must extend these exact identities and substitution rules, rather than introduce another generic system.

## Representation and alternatives

`GenericFunctionSymbol : FunctionSymbol` and `CheckedGenericFunction :
CheckedFunction` share native signature/body infrastructure while remaining
explicitly distinguishable definitions. Program `generic_functions` arrays own
these definitions separately from ordinary `functions`. All signatures are
collected before any body. The existing checker visits each source definition
once; calls substitute its signature, never its body.

`TypeParameterSymbol` owns one immutable `TypeParameterType`, carrying
`GenericCapability.GEN1_PLAIN_COPY`. Like accepted StructType/ClassType tokens,
this semantic type has no symbol, checked-body, ABI or stage backlink. Core maps
the symbol to an independent `CoreTypeParameter` descriptor owning that same
exact token. This is Core's parameterized type representation; introducing a
second canonical type universe would unnecessarily weaken exact type identity.
No checked symbol is retained by Core.

`CoreGenericFunction : CoreFunction` shares structured body storage and the Core
verifier, but occupies only the generic-definition array. `CoreGenericCall` and
its statement form retain an exact weak definition target and an independently
owned ordered type list. The Core verifier checks lexical type-parameter scope,
capability, exact substituted call signatures and ordinary concrete operations.
An ordinary call to a generic definition without its generic-call node rejects.

`TypeSubstitution` maps exact TypeParameterType tokens to exact types. It affects
only direct occurrences; GEN-1 permits no parameterized constructors. Every
concrete function parameter, local Place, field projection, block, loop target,
owner and object storage identity is recreated per instance. Value and statement
nodes are recreated; immutable global function, method, property/accessor, field,
cleanup and concrete type identities remain exact. No source/member lookup,
spelling replacement or parsing occurs during specialization.

`CoreGenericMonomorphizer` is a single compilation registry, partitioned by exact
`CoreGenericIdentity`, with ordered exact type-identity comparisons within each
partition. Hash tables serve lookup only. Ordinary callable traversal requests
roots, and an append-only FIFO worklist requests transitively needed instances.
The registered placeholder already owns its concrete signature. Explicit
`IN_PROGRESS`/`COMPLETE` states make recursion intentional rather than dependent
on syntax bounds. Phantom parameters participate fully in the key.

`GenericFunctionInstance` retains the exact immutable definition-origin token,
a weak reference to its Core definition, copied concrete arguments, deterministic
ordinal, state and exact weak caller identities. The origin token outlives the
parameterized body graph without retaining it. Core names are
`astra.gen.<definition-ordinal>.<instance-ordinal>`; existing LLVM internal
`astra.fn.<concrete-callable-ordinal>` naming remains authoritative downstream.
Both orderings are deterministic, and neither uses a user type spelling or a
physical type as identity.

The pass consumes ordinary Core bodies in place so already-resolved global
targets retain their exact identity. Its returned CoreProgram owns those bodies
and the completed instances, without generic definitions. Callers release the
consumed parameterized program before downstream work. CFG invokes
`CoreVerifier.verify_concrete`: generic definitions, unresolved generic calls,
and unresolved type parameters reject. Existing CFG/SSA/NABI/LLVM type verifiers
continue to reject unsupported parameter types without acquiring generic logic.

## Scope and capability

Type parameters are visible in the result, parameters, body and explicit call
type lists of their own definition. Builtin/reserved names and duplicates reject.
GEN-1 deterministically rejects shadowing an outer named type: existing concrete
ownership signature checks consult that namespace, so lexical shadowing would
require a separate namespace refactor with no benefit to this milestone.

Admitted types are bool; i8/u8/i16/u16/int=i32/u32; f32/f64; void*; every supported
numeric vector and bool mask. F64 vectors do not exist. Void, typed pointers,
arrays, slices, structs, classes and nominal handles are ineligible. The latter
carry lifetime/ownership/aggregate questions, not merely physical transport.

Copying, initialization, assignment, passing, returning, and branch/loop flow are
valid for T. Arithmetic, equality, ordering, bitwise/unary operators, truthiness,
casts, null contextualization, member/index access, address-of and dereference
are unsupported on T. Existing concrete operations and concrete owned/borrowed
contracts remain legal inside a generic body. Ordinary concrete CFG ownership
and flow validation applies after specialization; T itself owns no cleanup.

## Pipeline and profile policy

Source → checked generic definition → parameterized Core → exact specialization
→ concrete CoreFunction → ordinary CFG → ordinary SSA → ordinary NABI → LLVM.
There is no generic CFG, SSA, NABI profile or LLVM representation. A valid unused
definition is checked and Core-verified, and creates no downstream function.

Each substituted signature contributes its ordinary concrete channel/profile
requirements. Accepted NABI still selects the program's subsuming effective
profile, so a mixed f64/vector program uses fp64-v6. Isolated f32, f64, pointer
and vector instances qualify scalar-fp-v3, fp64-v6, scalar-ptr-v1 and vector-v4
respectively. GEN-1 neither assigns a maximum profile to a definition nor changes
that existing profile policy.

## Deferred scope

Generic structs/classes/members, generic ownership, handles/objects/slices/typed
pointers as generic arguments, parameterized type constructors, capability
syntax, inference/default arguments, const generics, specialization/code sharing,
interfaces, dynamic dispatch, function values, runtime generics and generic C ABI
remain separate milestones. Representation sharing may eventually optimize code
but must preserve distinct semantic instance identities.
