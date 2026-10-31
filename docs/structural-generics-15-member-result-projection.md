# Member result projection

The previous qualified compiler, `4015d52f7310dfdff75cbaccd765de582e79ba1cf4072badcce535c17030742a`, accepted Source checking of a free generic wrapper around a generic member, then rejected Core with `generic Class result requires concrete producer-origin projection`. Runtime receipt `member-wrapper-result-origins-before.json` preserves that failure. Further minimized failures exposed fixed Class results, constructed Class results, and fixed nominal results whose allocation origin depends on a receiver's type argument.

Source now projects result equations in the actual substitution context. It resolves typed locals, receivers, independent method arguments and extracted free helpers, using exact nominal type identities. Core independently reconstructs equations from its own nodes and resolves bodyless member headers to the exact closed implementation. Neither stage uses the other's result summary as proof. Requests use ordered identity keys, bounded inventories and memoized fixed points; Source retires its caches before releasing the analyzer.

A fixed Class result can still depend on an open producer argument. Such an abstract function carries provisional storage until specialization. This deferral applies only to unresolved generic equations. Nominal type, owner identity, moves, cleanup responsibility and callee-local escape checks remain binding. Every concrete instance must establish one storage domain, its exact cleanup and its immutable instance key. Concrete caller/heap joins are rejected with a source diagnostic.

Literal dead return arms contribute no result transport. Their source still undergoes nominal type and escape checking, and their checked declarations retain storage identities during lowering. Live caller and heap alternatives continue to participate in origin equations.

Three registered witnesses exercise actual resource-bearing Class values:

- `member-wrapper-result-origins.astra`: identity, caller and heap member producers; explicit/inferred wrappers, recursive helper extraction and dead opposite-origin returns.
- `member-fixed-Class-factories.astra`: fixed and constructed Class results, unused independent type arguments, integer and copied-record payloads, and both caller and heap factories.
- `dependent-fixed-Class-results.astra`: fixed nominal results through a typed producer local; separate caller/heap specializations, live alternatives and both ordinary and generic extracted heap factories.

Independent proofs destroy Source, poison its summaries, reconstruct Core equations, remove an exact closed member target, and mutate a concrete storage flag. Genuine wrong-specialization, consuming-boundary, dead-return type/escape and mixed-origin negatives remain exercised. Historical negative fixtures have not changed in this increment.

The frozen compiler `f7fab06477b4cce54b2c27d11f173c23d44d2ba660f53811318c76f0f8f32d84` passes 101 public source programs (1,718 checks), 639 opaque native-unit checks, 1,536 negative checks, 180 structural and 11 type proofs, the 39+13 historical storage controls, and 296 resource-bound checks. These standalone recipes include 702 unsuppressed Valgrind runs. The rebuilt affected registry finishes at 799/801; only the unchanged `concrete-result-chain` expectation and `open-argument` diagnostic remain failed, pending their previously requested separate consents. Exact receipts and qualified source hashes are in `structural-generics-15-member-result-projection.json`. Failed intermediate runs remain preserved.

This internal repair introduces no ownership spelling or binary schema. It does not establish G1–G8 completion or qualify the application and cross-unit async work still required by the task. `structural-generics-15-next-owner-locals.md` records the next minimized failures.
