# Shared native Class identity

The foundation source component uses existing native Class reference identity.
This does not add value equality for Shared handles or expose addresses.

For one exact native Class `T`, an ordinary typed helper takes two `borrowed
shared T` parameters. It compares null handles directly; two null handles match
and one null handle does not match a live handle. For two live handles it projects
both with `shared_borrow` as call-scoped arguments to a helper with two `borrowed
T` parameters, whose existing `==` compares reference identity.

Aliases and explicit shared clones name the same live payload. Independently
allocated equal-content objects remain distinct. Neither helper clones, acquires,
releases or consumes an owner. A containing Class can temporarily borrow its
owned shared fields into the typed helper without acquiring extra strong handles.
Creating a new retained span still acquires the owner that the new span needs.

This pattern is restricted by its signature to the exact native payload class.
Weak handles, other payload classes, foreign wrappers, direct Shared value
comparison and escaped payload projections are not added by this foundation.
Existing moved/released-owner checks and call-scoped borrow guards remain active.

The user authorized a narrow compiler extension if no suitable operation existed.
Inspection and execution found this existing operation sufficient; no compiler
semantic extension or pointer-cast workaround was needed. The focused identity
fixtures and verifier evidence qualify this existing route at O0/O2.
