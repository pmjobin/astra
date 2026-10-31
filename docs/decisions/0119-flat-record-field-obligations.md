# 0119: flat owning-record field obligations

Accepted for OWNED-STATE-SURGE-6-COMPLETION-1 on hosted native Astra.

A nongeneric synchronous stack-local struct may contain multiple independently
owned nominal Resource fields and scalar companions. Its ownership is derived
from those fields. Construction evaluates the complete initializer in written
order, independent of declaration order. The local becomes available only after
all fields succeed. Each successful Resource initialization acquires one exact
field obligation. Checked failure unwinds the producer's temporaries first,
then retires only acquired fields in reverse written acquisition order. Null is
a successful acquisition whose cleanup is null-guarded; it cannot suppress a
later live field's retirement.

A whole-record move to a fresh local transfers every field and its acquisition
rank, disarms all source Resource slots and preserves scalar values. Copies and
moved-source use remain invalid. Cleanup retires each live field exactly once,
including checked exits, early returns and moved-from records with null slots.
The first nominal cleanup still classifies a move-only local in root flow;
it is not the aggregate's runtime cleanup authority.

Core retains an ordered field plan plus per-field acquisition nodes. CFG keeps
that order and exact cleanup actions on successful-prefix edges; independent
field dataflow checks acquisition, move, reverse retirement and exits. SSA owns
one typed obligation per Resource projection and verifies events and move
completeness. Source-free native plans copy nominal field/cleanup identities and
ranks; correspondence checks them against SSA. LLVM retains exact cleanup-call
operands independently of generic LLVM validity. Tests mutate each boundary,
reject the defect, restore the original and verify it again.

This adds no aggregate calling convention. Owned Class fields in structs,
nested/generic owning records, field extraction, stored aliases, explicit record
release and owning aggregate transport remain deferred. Existing copyable
records and single-owner controls retain their own contracts.

See completion evidence.
