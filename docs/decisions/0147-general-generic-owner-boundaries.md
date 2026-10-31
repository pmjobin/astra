# General generic Class owner boundaries

Closed general-body Class applications now use ordinary synchronous native Class
owner boundaries. A factory can return an owned Vector; a concrete helper can
consume or forward it. Borrowed helpers can perform checked operations, return
complete copied records or extract an owned element. The old ExactHeapClass Bag
profile retains its historical boundary refusals.

The existing allocation-origin solver pins owned general-Class parameters and
results to heap ownership. Source callers still use explicit consuming moves.
Core, CFG and SSA independently verify the exact heap cleanup and the normal
owner lifetime, deferred argument reservation and exceptional rollback. A later
argument failure restores a pending caller owner. Once the callee is entered,
its owned parameter retires on success or checked failure. Borrowed parameters
do not become owners and cannot be moved out as the container itself.

Native parameter and result channels bind the original generic declaration and
exact instantiated Class ordinal once. Owned channels remain distinct from
borrowed generic channels. Detached signature checks reject erased or changed
owned channels; full native verification also checks the exact program Class
instance. Matching pointer widths do not authorize a different specialization.
No runtime type table, box, implicit reference count or external ABI change is
introduced.

The public witness constructs and forwards a Resource-owning Vector, checks a
later-argument failure with caller reuse, checks consuming-callee failure,
returns a checked record snapshot and extracts an entry whose lifetime outlasts
container cleanup. Empty snapshot failure and wrong specialization/copy/moved
uses have explicit controls. O0/O1/O2 output and unsuppressed Valgrind accompany
Core heap-origin, CFG/SSA rollback and source-free native erasure/specialization
corruption controls, each restored before verification. Native-only tests also
check one-time binding and detached channel mutations.

This profile is synchronous. Nested container arguments, owned generic child
fields, generic owning caches, symbolic free-generic transport and cross-unit
export still need their own compositional qualification. Full G1–G9 and A73–A84
acceptance remains outstanding; LAZY-1 Q4 stays HELD/INCOMPLETE.
