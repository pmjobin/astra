# GENERICS-14 source and verification boundaries

This map describes the implementation, not completed qualification. Runtime
receipts and the final milestone findings govern which programs actually pass.

| Stage | Original boundary | Task implementation and independent authority |
| --- | --- | --- |
| Source / syntax | Generic syntax exists; original tokens and byte spans remain owned by the parsed program. | The parser grammar is unchanged. Concrete typed syntax is added to the same owner. Generated copy code and separately generated structural comparison code cover the supported schema. Neither rewrites source text. |
| Binder | Template parameters, references and member candidates have declaration and scope identities; member completion is bounded. | Instance syntax, scopes, declarations and references receive distinct identities. Original rows remain authoritative. The consumer checks mapped targets, scopes, visibility, source tokens and spans. |
| Typecore | Symbolic/closed generic types can be represented; representation is not executable admission. Generic calls and policies remain deferred in the older native profile. | Ordered TypeEdges drive explicit selection, exact inference, nested substitution, nominal materialization and concrete signatures. Instance keys retain declaration source identity, enclosing instantiation and arguments. The separate checker reconstructs those facts without calling the instance builder. |
| Flow | Ownership, borrow channels, construction and dependent obligations require individual proofs. | Concrete bodies enter ordinary checked/Flow analysis. A normalized argument view adds the approved borrowed receiver before source arguments. Independent loan verification consumes that same view. Original source calls remain intact. |
| Core | Place authority is separate from detached values and owner transfers. | Existing scalar, aggregate, call and owner lowering consumes concrete signatures. Operation 13 allocates a bounded empty Class. Operation 14 reads a buffer length from an authoritative place, avoiding a duplicable owning-buffer SSA value. Separate source/schema verification reconstructs both operations. |
| CFG / SSA | Control edges, block arguments, cleanup, loans and def-use have independent verifiers. | Actual specialized bodies use these stages. No trusted generic bypass or alternate C application body is introduced. Original mutation families remain mandatory. |
| LLVM / ABI | Native x86-64 layout, private aggregate transport, narrow scalar public C ABI and module-owned caches are independently checked. | Specialized private names include canonical semantic identity and qualified target/layout policy. Concrete record layouts and borrowed Class pointer channels are verified against actual LLVM types and instructions. Allocation guards and once-only retirement remain observable. Public C generic ABI is deferred. |
| Driver / consumer | An out-of-source C0 build produces the Astra-written query component. | That component performs application checking, specialization, IR and LLVM emission itself. Application linking uses its object. Separately compiled C0 applications supply independent oracle observations. This does not claim whole-compiler admission or Stage 1. |

## Bounded generic policies

The current C0 sources `bootstrap/source/generic-capability-rules.vala`,
`bootstrap/semantic/generic-capabilities.vala` and the operator checker are the
capability authority. Native specialization admits the explicit supported
capabilities only: Numeric and Ordered for numeric primitives, Eq for numeric,
boolean and string types, Bitwise and Shift for integers, and Ownable for the
bounded Class domain. Capability implication is not invented. ExactHeapClass
and generalized storage/capability policy remain unqualified.

Symbolic operator checking requires exact parameter operands and the operation's
explicit capability. Concrete bodies are checked again after substitution.
There is no implicit numeric promotion or optimistic copyability of `T`.
Nested records retain separate nominal identities even when layouts coincide.
Owning generic-record fields rejected by C0, generic owning-record type arguments
without a complete policy, recursion requiring unbounded materialization,
foreign/async/throwing generics and unsupported Class shapes remain named
deferrals. The approved Class domain and its limits are recorded separately in
the receiver ABI proposal.

## Reading whole-source ledgers

The ledger consumer is built against both the exact initial sources and current
sources. It records original parsed nodes, owning function declarations, byte
spans, syntax kinds, checked types/flags/deferred codes and raw Flow observations.
The same initial source snapshot can also be observed by the current consumer.
Each file and product has a content hash. Node ordinals are local to a program;
cross-version comparisons use source identity and spans.

A recorded TypeId is not a Flow, IR or execution proof. A zero checked use can
name structural syntax or a node unvisited after the first reported error.
Such nodes stay explicit, with the whole-program error attached. The ledger
does not turn an early failure into acceptance of later files. The frozen real
generic witnesses provide the separate, source-bound execution progress matrix.
