# ADR 0085: Proposed native async lifetime and executor contract

**Status:** Proposed / user review required

**Date:** 2026-10-03

**Campaign:** ASTRA-ASYNC-CONTRACT-1, revision 2

**Baseline:** 5039f554f511e0580ec9de8f8ed46e7bc273c268

The inspected registry ends at [0084](0084-owned-buffer-exchange.md). This ADR
reserves the next number for a design/model recommendation; it accepts no source
semantics or Linux profile. The founding Bible §§24–25 and roadmap Q01–Q06
require readable native async with exact function/environment/lifetime authority.
Existing direct calls, lexical borrows and caller-owned Class results do not
establish deferred task capture, stable frames or external registration quiescence.

Recommend the single [proposed contract](../architecture/async-contract.md):
deferred unique tasks, one consuming observation, explicit join/cancel drain,
sealed parent-local suspension loans, stable heap frames, explicit cooperative
executor, three-way completion and generated continuations before full closures.
Its alternatives, compatibility costs, source witnesses, invariants and deferred
extensions are defined there, avoiding a second normative copy here.

The **user-approved direction** from 2026-10-03 is native-kernel-first Linux,
including justified upstream RC dependencies, explicit missing-capability errors,
portable semantics and manual application pumping. R2's verified
`references/user-platform-direction-2026-10-03.md` and the user's continuation
message supply provenance. This bounded direction amendment leaves compiler-side
GLib and separately selected interoperability unchanged. The proposed
[Linux profile](../platform/linux-async-profile.md) selects one-shot io_uring
timers/cancel, v7.2 kernel source audit floor and, after R3, a thin liburing-assisted
boundary at the inspected 2.15 helper source floor; those choices remain reviewable.

Consequences include explicit join requirements, narrower suspension borrowing
than synchronous borrowing, initial frame allocation, no shared/multi-await tasks,
and delayed result delivery until external payload release. The bounded executable
model supplies finite lifecycle evidence; it is not proof of emitted code or
Linux runtime behavior. Validation records
qualifications and the review lists the
remaining semantic/profile decisions. Q01–Q06 and Q12/Q16/Q25 remain OPEN.
CALLABLE-1/ASYNC-1/ASYNC-IO-1 have not started. No production implementation,
kernel/security/package mutation, push or tag is part of this decision.

## Proposed revision history

- R2 at 7674514: original design/model qualification retained unchanged in Git
  and its original validation/evidence; not semantic approval.
- R3: targeted correction review adds
  scoped request/drain, observed publication predicates, cold ownership/admission
  and pending observation mapping. L17 corrected; liburing-assisted maintenance
  tradeoff replaces the flag-absence premise. The new qualification
  is bounded model evidence. ADR status remains Proposed; all questions remain OPEN.
