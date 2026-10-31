# Typed native closure parameters

Native Closure and CheckedClosure parameters now retain their exact environment,
error bound, function signature, record groups and borrow/transfer contract.
Their environment and all nominal signature components must have the required
exported declarations. The native signature records the typed closure shape;
the existing opaque pointer representation does not erase those facts.

The new three-layer graph reuses the producer-owned exception root. Its dependent
library owns a generic environment declaration with an independent Resource field
and accepts callbacks supplied by the later client. Borrowed checked invocation
returns a record, fails and succeeds again using the same environment. Consuming
invocation retires its environment on both normal and exceptional exits. An
ordinary closure uses a distinct specialization with a record-valued environment.
The exact Resource trace proves those lifetimes and reverse declaration-order
cleanup, independently of the returned values.

All eight mixed O0/O2 combinations and O1 pass with nine unsuppressed memory runs.
Producer implementation copies are deleted before consumer compilation. Forged
environment, checked-error and ownership declarations reject against the original
native signature before emission. Missing moves and use after transfer remain
genuine source negatives.

Compiler `2325d578b5495f8ad21de7455efc0f6f673a07af8bc783f05da3f2ada730840c`
passes 109 source programs (1,854 checks, 327 memory runs), 199 negatives
(1,592 checks), 752 opaque-unit checks (168 memory runs), the expression matrix
(168 checks, 24 memory runs), and all 203 structural proofs. Source, recipe,
binary and receipt identities are in `structural-generics-15-native-closures.json`.
The affected registry and final G7 have not been rerun for this compiler.

The first ownership witness used IDs outside the existing observer's 1–255
range and failed in that observer before testing closure lifetime. The corrected
201–204 inputs preserve the algorithm and produce the required cleanup trace;
the first failure remains in its separate runtime receipt.

A following interface probe exports successfully but emits a class-style virtual
prototype that the interface grammar rejects on import. Fix that declaration
form and pin the interface role, then continue actual native async suspension and
cancellation. Wider ownership families, callback preconditions, the useful
application and remaining G2–G8 qualification are still required. Historical
expectations remain unchanged; no milestone PASS or report update is claimed.
