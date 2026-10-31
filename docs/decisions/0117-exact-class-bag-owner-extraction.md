# 0117 — Exact-Class Bag owner extraction and replacement

Status: implemented bounded extension in OWNED-STATE-SURGE-6; campaign acceptance
remains PARTIAL because owning-result lazy properties and multi-owner records
are unresolved. This extends ADR 0101's finite recipe without widening T.

`take(int index)` removes an occupied pointer carrier, shifts later carriers
left, nulls the vacated last slot, decrements count and returns the exact heap
Class owner. Capacity and object addresses stay unchanged. The result must enter
one fresh named owner; it is subsequently movable, independently releasable and
subject to the existing checked-scope cleanup rules. Taking the only item leaves
an empty reusable backing. Negative, empty and past-last indices trap before
mutation. This new API follows the existing fatal index contract, not a checked
index result.

`replace(int index, owned T value)` consumes a named exact heap owner. Index and
nonnull guards precede mutation. The incoming pointer is installed before the
old element's exact destructor and deallocation; count/capacity and other object
identities stay unchanged. Destructors cannot throw. A failed checked producer
before this call leaves the old element intact. There is no new implicit reserve.

The four prior methods and their order are preserved. Definitions may retain
only the five original recipes, or add the two new finite recipes. The new take
recipe is `var value = this.entries.take(index); return move value;`; replacement
is one direct indexed consuming statement. Arbitrary generic method bodies,
stored slot aliases, nested slot elements, caller-backed element owners and
foreign/record element widening remain rejected.

Checked extraction retains the exact element and storage identity. Core requires
one fresh acquisition. CFG retains acquisition context and invalidation; SSA
pairs extraction with an immediate ACQUIRE event and replacement with an
immediate MOVE event. Pointer origin and cleanup are reconstructed independently.
The native recipe requires the exact PTR heap result/parameter class and I32
index. LLVM retains complete helper instruction/edge/operand correspondence for
bounds, stable shift, last-slot clearing, incoming-first commit and old cleanup.
An indexed loan cannot cross reserve/take/replace or container destruction.

The 16-byte PTR/I32/I32 slot descriptor and native unique Class layout retain
existing meanings. No refcount, hidden runtime library or generic erasure is
introduced. New proofs and actual public driver/memory witnesses live in
`tests/owned-state-6`; old Bag tests and goldens remain intact.
