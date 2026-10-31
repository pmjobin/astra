# ADR 0060: Ownable generic parameters and ownership transfer

Status: accepted for ASTRA-GEN-OWN-1.

GEN-BORROW-1's later user-approved [ADR 0094](0094-call-scoped-generic-borrowing.md)
supersedes the deferred borrowed-T item only for its finite Resource/Class loan
scope. The original decisions below remain the historical GEN-OWN-1 contract.

## Context and decision

GEN-1's implicit GEN1_PLAIN_COPY authority permits ordinary value transport. A
Resource or transferable native object instead carries an explicit ownership
contract. Giving the same unknown parameter both authorities would permit
copying responsibility. GEN-OWN-1 therefore introduces an exclusive generic
transport mode selected by the explicit built-in Ownable requirement.

Ownership remains a contract over an exact type identity. Parameterized Core
retains cleanup responsibility without selecting a destructor or physical ABI.
The existing Core monomorphizer selects the concrete Resource or Class contract.
Structured ownership proofs run during definition checking and independently
when verifying Core, before any concrete instance exists.

## Frozen decisions

1. Ownable is a built-in semantic generic capability in the existing namespace.
2. Ownable is compile-time only.
3. Ownable has no runtime witness.
4. Ownable has no dictionary.
5. Ownable has no runtime type descriptor.
6. Ownable authorizes `owned T` contracts.
7. Ownable authorizes explicit ownership transfer through `move`.
8. Ownable does not authorize copying T.
9. Ownable does not authorize ordinary plain-T value transport.
10. Ownable does not imply Eq.
11. Ownable does not imply Ordered.
12. Ownable does not imply Numeric.
13. Ownable does not imply Bitwise.
14. Ownable does not imply Shift.
15. None of those value capabilities imply Ownable.
16. GEN1_PLAIN_COPY and Ownable occupy different generic transport domains.
17. Unconstrained generic parameters retain GEN1_PLAIN_COPY exactly.
18. Eq/Ordered/Numeric/Bitwise/Shift parameters retain GEN1_PLAIN_COPY exactly.
19. A parameter explicitly constrained by Ownable has OWNABLE mode and does not
    implicitly carry GEN1_PLAIN_COPY. Mixing Ownable with a value capability on
    the same parameter is rejected in this milestone.
20. Nominal Resource types with the existing exact release contract satisfy Ownable.
21. Native ClassType satisfies Ownable under existing transferable owned contracts.
22. Scalars do not satisfy Ownable in GEN-OWN-1.
23. Vectors and masks do not satisfy Ownable.
24. void* does not satisfy Ownable.
25. Ordinary StructType does not satisfy Ownable.
26. Concrete generic struct instances do not satisfy Ownable.
27. Slices, arrays and typed pointers do not satisfy Ownable.
28. Ownable T may appear as `owned T` in function parameters and results, and as
    an explicit type argument satisfying another Ownable requirement.
29. Plain T value positions are disallowed for an Ownable parameter.
30. `borrowed T` is deferred.
31. `owned T` struct fields are deferred.
32. `owned T` class fields are deferred.
33. Owned properties are deferred.
34. Generic owned local declarations are not introduced. The only generic owner
    slots are compiler representations of incoming owned parameters.
35. Generic ownership state is checked before concrete instantiation.
36. Double move and moved-use errors reject during generic-definition checking,
    including invalid unused definitions.
37. Concrete instantiation does not discover or repair generic move correctness.
38. Parameterized Core retains exact generic ownership contracts and source owners.
39. Monomorphization converts these contracts to existing Resource/Class contracts.
40. Existing CFG ownership-flow analysis receives only concrete ownership.
41. Concrete Resource cleanup/release behavior remains unchanged.
42. Concrete object destructor behavior remains unchanged, including no-deinit classes.
43. Concrete object-storage provenance remains unchanged, including empty classes.
44. Returning an incoming owned generic parameter is permitted: its ClassType
    specialization refers to caller/ancestor-owned storage.
45. Returning a callee-local owned ClassType storage remains prohibited.
46. GEN-OWN-1 avoids creating that case by excluding arbitrary generic owned locals,
    construction, local owner moves and null construction.
47. Ownership transfer preserves exact resource and ObjectStorage identity.
48. Semantic ownership capture occurs left-to-right.
49. Physical transfer commits under existing OWNBOUND rules, after argument evaluation.
50. Traps remain non-unwinding; result-computation traps do not run cleanup.
51. There is no generic cleanup runtime, callback or destructor function pointer.
52. Generic definitions have no ABI before specialization.
53. Resource and Class specializations may receive different concrete ABI plans.
54. These ABI differences do not alter generic source semantics.
55. No new NABI type or profile is required.
56. No heap allocation, owner header, boxing or resource/object copy is introduced.
57. Future Copy/Move aggregate semantics must extend this system rather than
    reinterpret Ownable as ordinary moveability or copyability.

## Representation and consequences

`GenericCapabilityIdentity.OWNABLE` and the existing capability symbol/set retain
exact requirement membership. `TypeParameterType.transport_mode`, exposed by
Checked and Core parameter objects, is PLAIN_COPY unless Ownable is explicit.
Its legacy `capability` accessor returns GEN1_PLAIN_COPY only in that mode.

Checked owned parameters use the existing parameter contract and incoming
`LocalSymbol`; ownership and type identity remain separate. Core uses
`CoreCleanupContract.for_parameter` as a compile-time responsibility contract
keyed by exact TypeParameterType. It has neither external cleanup symbol nor
Class/destructor metadata. Owned parameter acquisition, arguments and returns
reuse their existing Core nodes. The contract is removed by the same
`CoreGenericMonomorphizer` that handles function and struct instantiation.

The OWNED/MOVED/RELEASED possibility set is a stage-neutral semantic authority.
The structured proof for generic owners uses its OWNED/MOVED subset and tracks
branches, short-circuit effects, returns and loop backedges without constructing
CFG over T. Independent Core verification rebuilds this proof from Core events.
No proof object survives into specialized ownership or native execution.

Direct generic result forwarding uses the existing return-producer capture path.
The concrete Resource verifier now accepts a direct native owned producer with
one exact consumer; Class forwarding retains its caller result-candidate and
storage-provenance requirements. This requires no intermediate owner local.
Ordinary Resource source syntax retains its existing move/null return policy.

For `relay<Resource>`, the physical signature is owner PTR → owner PTR. For
`relay<Counter>`, it is candidate PTR, owner PTR → owner PTR. A forwarded incoming
object may leave the candidate unused. No candidate storage appears in generic
source semantics or in a Resource specialization. Empty and no-deinit classes
still carry ownership responsibility and exact storage identity.

See [language](../language/generic-ownership.md), [Core design](../ir/generic-ownership.md)
and qualification. Aggregate Copy/Move, aggregate
arguments, generic fields, borrowed T, parameterized Struct*, generic members,
classes and interfaces remain separate campaigns.
