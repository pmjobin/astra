# ADR 0087: Shared enum and checked-error foundations

**Historical supersession:** [ADR 0090](0090-native-exceptions.md) records the submitted approved class-exception/message direction. This proposal's enum-backed errors, capture/prefix-try and mandatory A+C async direction are superseded where inconsistent. Its ordinary enum foundations and history remain preserved.


**Status:** Proposed / detailed source and ABI approval pending

**Date:** 2026-10-04

**Campaign:** ASTRA-ENUM-ERROR-CONTRACT-1

**Baseline:** a7cb205b6ac9b4341455f0798f4af041206de134

The actual decision registry ends at 0086. This checkpoint reserves 0087 for a
design/model proposal, without changing any delivered language contract.

The user approved nominal type-safe payload enums, ordinary structured error
values using the same machinery, explicit handling plus keyword propagation
(A+C), and errors before source async. The packet's USER-DIRECTION.md records
the visible conversation; it is not an invented signed approval or host receipt.
The earlier unexecuted A1-R3-EXPLICIT draft is superseded as an implementation
plan. Its bytes/history and R3 lifecycle evidence remain intact.

Recommend the [single contract](../architecture/enums-and-errors.md): qualified
variant construction, valid initialized active payloads, exhaustive statement
matching, type-wide derived copyability, whole consuming matches, bounded
inspection borrows and incoming-first replacement. Ordinary generic Result and
VoidResult plus enum-scoped ArrayResult composition provide concrete scalar,
record, void and owned-buffer success paths without misusing current plain T.
Checked native `throws E`, explicit `capture`, prefix `try` and exact lexical
handlers reuse those values. Argument reservations commit with invocation and
have explicit abort cleanup; current fatal traps retain their policy.

The strongest detailed alternatives and their costs are in the nine-item
review table. The bounded carrier
plan requires future versioned sum/fallible native capabilities; no ABI number,
foreign enum layout or serialization is selected here. No dynamic heavyweight
unwinder, hidden box, global pending error or new production dependency is added.

Consequences include explicit generic constructor arguments, ArrayResult/
VoidResult family names, no initial payload equality/default, arm-limited
borrow access, and explicit joins before concurrent async error exit. These
costs buy exact transport/validity without requiring general STRUCT-MOVE,
all generic containers, dynamic text or full closures before useful errors.

ENUM-1 and ENUM-OWN-1 have named acceptance matrices,
followed by ERROR-1 and revised ASYNC-1 with A+C, then ASYNC-IO-1. One substantive
review of this checkpoint should enable the ENUM-1 implementation order; another
abstract enum/error survey is unnecessary. Detailed grammar, semantic and ABI
approval remains pending. The bounded model qualification
does not accept this ADR or deliver native enum/error support.

Q05/Q30 have approved direction and proposed detailed answers; all Q01–Q35 stay
OPEN. Q10/Q11/Q13/Q16/Q24/Q25/Q34 coordination is explicitly limited by the
[dated roadmap amendment](../vision-and-roadmap.md#enum-error-contract-1).
Native-kernel-first policy, CALLABLE/V01–V03 and R3 retirement/cancellation proofs
remain unchanged. LAZY-1 is near-term; PERF-01 is Candidate / not scheduled.
