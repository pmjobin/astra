# ADR 0089 — Bounded owning and generic enums

**Status:** Accepted source scope for E2-OWNED-GENERIC-SUMS; implementation qualification PARTIAL.
**Approval:** Pierre-Marc's actual conversation message was: “I approve
E2-OWNED-GENERIC-SUMS as specified in SOURCE-APPROVAL.md. Proceed with ENUM-OWN-1.”
The incoming packet's approval template was a reference, not authorization.
Starting commit: `60329eb783d3718d1081111d1fca73cf0911b58d`.

Ordinary generic outcome definitions need exact nominal applications, copied
record outcomes, a genuine zero-field success and unique array payload transport.
Extend the existing enum producer/storage mechanism rather than adding special
Result semantics or general aggregate SSA. Applications retain an immutable
ordered argument key, including phantom arguments. Direct `owned T[]` fields
derive the existing array-element premises; known applied signatures import only
those exactly substituted premises, including acyclic nested applications.

One all-variant authority derives copied or owning transport. Any owned array or
nested owning enum makes the complete type move-only, including its empty cases.
Named transfers spell `move`. Constructor/call argument capture reserves named
owners until that consumer commits. Replacement captures the incoming value
before active old cleanup. Inspection lends readonly arm views; consumption
transfers exact selected fields and disposes ignored fields in reverse order.
Normal cleanup follows the active tag and reverse initialized-field order.
Fatal allocation paths remain non-unwinding.

Existing static ownership flow is extended through Core/CFG/SSA. Bounded local
live flags handle structured joins in LLVM; independent verifiers establish
initialization, exact binding, loan lifetime and disposal before those flags can
be used. Flags are implementation state, never authority to copy or free a moved
value. Owning sums select `owned-sums-v13`, with transfer inputs and independently
identified caller result storage. E1 copied sums retain `sum-values-v12` and its
physical channels. No enum heap box, runtime reference count or generic dictionary
is introduced. Existing allocator/free calls own the actual array allocations.

The first subset excludes enum-containing structs/classes, enum collections,
Resource/Class and stored borrowed/text payloads, checked errors, async and the
Linux provider. Concrete/generic copied records remain eligible enum payloads.
Copyable enum function values do not confer record-field or buffer-element
storage eligibility. General borrowed enum parameters and inferred parameterized
enum locals are excluded; those locals spell an applied type explicitly.

[ADR 0087](0087-shared-enum-and-error-foundations.md) remains Proposed, and
[ADR 0088](0088-native-copyable-enums.md) remains the accepted E1 decision.
This bounded E2 approval does not accept their remaining design decisions or
authorize ERROR-1. See the [source guide](../language/enums.md),
[IR contract](../ir/enums.md), [native profile](../abi/native-sum-values.md),
[ordinary library definitions](../library/base.md) and
actual validation limits.
