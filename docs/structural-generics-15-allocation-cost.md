# Argument-vector allocation cost and bounds qualification

The registered resource-bound recipe now passes completely on production compiler
`f8508c6cd385c95cacc01293f9fbcbb3d2ee8e8b307b46d5c1e9b46f538b85cb`.
Ordinary Meson execution retained its nonzero allocation perturbation, 180-second
invocation deadlines, 360-second registration deadline and every existing
acceptance/refusal assertion. Total registration time was 231.90 seconds. This
qualifies that regression, not the full registry or milestone.

The shared repair reserves the known number of entries when copying immutable
type-argument vectors, their canonical specialization keys and Core call
arguments. It preserves entry order, exact type identities, constraints, cache
keys, bounds and ownership facts. No fixture or application names participate.
Fresh substitution per argument remains unchanged. Source arguments still require
all the same independent proofs before specialization.

The earlier unreserved compiler exceeded the invocation deadline under Meson's
allocation perturbation. Captured stacks showed repeated pointer-array growth
inside Core specialization spending time clearing allocator memory. Reserving
only two temporary arrays was insufficient; reserving the complete argument
vectors passed. A further local-substitution reuse prototype gave little benefit
and was not integrated. Measurements include varying concurrent build load and
are not an isolated performance benchmark.

The isolated reservation-only compiler passed the 142-check seeded generality
matrix, 40 unsuppressed Valgrind runs and all 1,648 checks for 206 structural
negatives before integration. The production compiler passes all 245 generic
proof groups, 14 type/origin groups and 21 native standalone groups. Existing
historical negative expectations remain unchanged.

The bounds harness now retires both its timing wrapper and compiler on invocation
timeout or interruption, then re-raises the failure. It retains the original
deadline and result checks. Earlier timeout attempts remain failed evidence. The
three existing QEMU regressions remain explicitly authorized; no additional VM
activity is introduced.

Two registrations are added: `structural-generics-15-generality` and
`structural-generics-15-historical-observations`. They run the already exercised
transformation and exact-source controls through ordinary Meson. All 9,376 prior
registrations, profiles, deadlines and serial barriers are retained; the resulting
inventory must contain 9,378 names. The old full registry attempt does not qualify
this increment. A complete rebuild, clean strict compiler, final registry and
application/staged reruns remain required. Fixture-consent decisions and canonical
publication also remain open.
