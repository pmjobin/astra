# ADR 0088 — Native concrete copyable enums

**Status:** Accepted for E1-CONCRETE-VALUES only.
**Approval:** Pierre-Marc replied “I approve.” to the explicit ENUM-1 draft source
approval gate in this conversation. The packet itself and its template approval
sentence were read-only references, not authorization. Baseline:
`c2e79bae674d7240cdc66f1b58e13e8763a84db1`.

Implement closed nonempty nominal enum declarations, qualified positional
constructors, initialized value locals/assignment, read-only independent native
parameters, caller-provided result storage, exhaustive statement matches,
independent selected payload copies and equality for payload-free enums only.
Payloads are existing scalars/vectors/masks/raw void pointers, eligible concrete
copyable records including concrete generic records, and acyclic nested concrete
enums. Complete all-variant checking is separate from generic, zero, Eq and array
storage capabilities.

The concrete problem is that alternatives have different initialized payloads.
Flattening all variants into the existing record ABI would require reading inactive
fields and alter old signatures. Use bounded explicit sum producers and storage
slots through Checked/Core/CFG/SSA. New native `sum-values-v12` transport uses
independent stack snapshots and a target-derived tag plus maximum active payload
carrier. No heap box or new runtime dependency is introduced. Old native and C
signatures retain their profiles and physical channels. Pointer copying gives no
ownership or pointee lifetime guarantee.

Exact immutable nominal/variant/field/binding/instance tokens and retained input
contracts survive predecessor destruction. Each verifier derives initialization,
active-field validity and complete coverage independently. Native plans and LLVM
artifacts verify exact field paths, copy operands, storage roles, call channels and
publication ordering. Malformed-output checks first establish ordinary LLVM
validity, require Astra rejection, and then verify the restored artifact.

This implements the necessary first subset of D01/D02/D03/D05/D08. [ADR 0087](0087-shared-enum-and-error-foundations.md)
and the full [enum/error proposal](../architecture/enums-and-errors.md) retain
Proposed status outside this subset. D04/D06/D07/D09, recoverable reservations,
owning/generic enums, checked errors and source async are not accepted here.
ENUM-OWN-1's existing matrix is the next gate,
followed by ERROR-1 and revised A+C ASYNC-1. All seven tracks, Q01–Q35 and the
E01–E04/V01–V03 history remain.

See the [current source guide](../language/enums.md), [IR](../ir/enums.md),
[ABI](../abi/native-sum-values.md) and actual qualification.
