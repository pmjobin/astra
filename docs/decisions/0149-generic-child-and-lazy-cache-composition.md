# Closed generic child fields and owning lazy caches

A closed general-body Class application now participates in ordinary owned
native fields and receiver-borrowed properties. A lazy owned property may cache
that exact Class application. The original factory transfers heap ownership;
the public getter observes the receiver's cache without acquiring or escaping
it. Legacy ExactHeapClass Bag fields and caches retain their historical refusal.

Core, CFG and SSA admit a general Class result through either its existing heap
owner boundary or an exact declared receiver-borrow getter. Their ordinary
property, field, cleanup and ownership verifiers still check the full channel.
An arbitrary borrowed function result does not gain that authority. All stages
retain the ownership graph checks through Classes, records, slots and caches.

Native Class fields now carry their exact owned child Class ordinal, separate
from physical pointer storage. The plan freezes that declaration; erasure or a
replacement field rejects independently. The native dependency walk follows
those child edges as well as slot/record/cache edges. Each owned cache binds its
original factory and payload Class once; changing either mutable test descriptor
cannot erase or redirect its original ownership. These are compiler metadata,
with no emitted RTTI table or change to external C/GObject ABI.

The public composition uses a derived receiver's computed virtual property over
a checked lazy Vector of owning records. Two receivers have distinct payload
identities and initialization paths. A failed first attempt retires all record
fields; retry succeeds once; receiver movement preserves Ready state; user
teardown precedes exact cache retirement. The same application tests a direct
owned generic child and a borrowed projection. Computed virtual getters continue
to execute: the failed first read returns zero and the later retry returns one.
A recursive generic cache initializer traps before publication at O0/O1/O2.

A second program retains a nongeneric receiver owning the generic cached value
in an ordinary cooperative async frame. Its temporary getter loans finish before
suspension. Completion, checked failure after suspension and repeated cancellation
followed by cancel-and-join all observe exact receiver/cache/record retirement.
Generic container parameters to async functions remain excluded; no cached-value
loan is transported across an unproved suspension. The factory itself remains
synchronous and cache synchronization is still outside this campaign.

Independent proofs corrupt and restore Core heap ownership/child cleanup, CFG
borrow observations, SSA factory registration, native field/cache declarations,
LLVM cache disarm state and async frame acquisition/retirement. Later physical
checks run after predecessor graphs are released. Public execution and
unsuppressed Valgrind use exact traces at O0/O1/O2.

The wider regression selection exposed obsolete older refusals for Class-owning
records and explicit record field extraction, both implemented and qualified by
Surge 10 G1. The former is now a positive O0/O1/O2 plus Valgrind control; extraction
keeps an explicit invalid-copy counterpart. The legacy Bag diagnostic is restored
without changing its refusal. Earlier failed receipts remain evidence, not PASS.
Generic template property declarations, broader interface/non-null composition,
G6–G9 and A73–A84 still require their own implementation and qualification.
LAZY-1 Q4 remains HELD/INCOMPLETE.
