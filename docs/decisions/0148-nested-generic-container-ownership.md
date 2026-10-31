# Nested general containers and complete ownership graphs

Closed general-body Class applications may use another closed general-body
Class as their storage argument. The same Vector declaration therefore owns
Vectors of copied records, Classes or owning records. Both application levels
retain exact declaration and argument keys. Legacy ExactHeapClass recipes keep
their historical nested-storage refusal.

Nested containers use ordinary heap owner transfers. Inner slots move with the
inner Class owner and are destroyed exactly once by its ordinary destructor.
Outer iteration lends the inner Class only for readonly calls; inspecting its
slot count or capacity is pure, while reserve, take and other mutations remain
excluded. No persistent slot pointer, erased owner or runtime type tag is added.

The native Class plan now freezes every original slot declaration, including
Class-valued slots. Changing the inner Class ordinal to an equally wide but
different specialization rejects after all predecessor graphs are released.
Core and CFG independently reject substituted nested specialization keys.

A counterexample exposed an existing ownership-graph gap: Root owning slots of
Packet, where Packet owns Root, previously passed Source checking. Source,
Core, CFG and SSA now traverse record fields as well as Class and slot edges.
The invalidation walk follows those same record nodes. Native verification
independently detects cycles through slot Class identities, complete owning
record cleanup plans and owned caches. A separately authored native model checks
a valid graph, a cyclic graph and restoration without compiler builders.

The initial independent native test had an invalid declaration acquisition rank;
that failed receipt is retained. Its declaration now correctly uses unacquired
field ranks, distinct from the ranked transport responsibilities. The restored
thirteen-suite selection qualifies nested Class, copied-record and owning-record
containers at O0/O1/O2 and under unsuppressed Valgrind, plus source and independent
stage corruption controls. This does not establish direct generic child fields,
generic owning caches, symbolic free-generic transport or a cross-unit ABI.
Full campaign acceptance remains outstanding; LAZY-1 Q4 stays HELD/INCOMPLETE.
