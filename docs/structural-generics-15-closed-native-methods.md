# Selected closed generic methods across native units

Native export now accepts selectors such as
`NativeMethods.Counter<int>::merge<i64,NativeMethods.Answer<int,i64>>`.
Selection resolves through ordinary class/member lookup, recursive type
resolution and declared constraints. It demands the actual method specialization
without synthesizing a callable implementation or transporting dummy owners.
The selector's namespace supplies normal scope for its type expressions.

The interface contains generic declaration signatures and the finite inventory
of exported closed tuples. Import materializes that inventory even when a
particular consumer does not call every exported method. It never specializes
an imported implementation body. Calling an unexported tuple remains a source
error. Selector order and selecting a method without a separate owner selector
both work; aliased duplicate tuples reject before output artifacts appear.

Source, Core, CFG, SSA and LLVM module binding include the ordered method tuple
in callable identity. Method type arguments must reference the required exported
nominal declarations even when absent from the physical parameters/result. Three
independent proofs replace an erased argument with a different admissible Class
while preserving the physical ABI. Each stage rejects the mismatch against the
original native declaration after its predecessor representation is destroyed.

The new leaf/middle/client chain uses a generic Class with extra state, a typed
property, a record-returning method, a method with two independent arguments and
an erased constrained Class argument. The later client supplies callback bodies;
the middle forwards them to the leaf. The client imports only the middle.
Producer implementation copies are deleted before consumer compilation. All
eight mixed O0/O2 combinations and O1 pass with nine unsuppressed memory runs.
Unexported tuples and genuine capability violations remain negative.

Compiler `cbc9f1b55a687874efeea87b56e46b67300139bfad97581a8667c4346aa38160`
passes 109 source programs (1,854 checks, 327 memory runs), 199 negatives
(1,592 checks), 678 opaque-unit checks (150 memory runs), the expression matrix
(168 checks, 24 memory runs), and all 200 structural proofs. Exact qualified
source, recipe, binary and receipt identities are in
`structural-generics-15-closed-native-methods.json`. This is focused increment
evidence; the affected registry and final G7 have not been rerun.

The retained first consumer run exposed missing imported-inventory demands and
the older Core/CFG/SSA native keys that omitted the method tuple. Both are fixed.
The first CFG destruction proof retained a nested Vala expression temporary;
generated C confirmed that reference. A helper now releases it before the
unchanged destruction assertion. The corrected proof reaches the intended
native identity rejection. The lexical-shadow probe was invalid under the
existing name-collision rule and supplies no native-method credit.

Native callback preconditions for scoped indexed lookup, broader owned method
channels, checked/interface/async contracts, the useful application and remaining
G2–G8 qualification are still work. Historical fixture expectations and pending
consent requests remain unchanged. No milestone PASS or report update is claimed.
