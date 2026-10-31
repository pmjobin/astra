# Frozen generality challenge: inventory reconciliation

Requirements frozen after the first real indexer program compiled and executed,
before any challenge implementation or integration. Initial compiler SHA-256:
`b674fc114453113908babba4a7d5eaf5064a610b3ea7e0eaeca4c1eb453e7ece`.
The initial indexer execution receipt is
`runtime/native-current/index-mono-ip7ijler/checks.json` in the project work area.
It is an initial monolithic program, not qualified completion of the indexer.

The same Codex session authors both applications. This is a different frozen
requirement, not an independently authored or permanently held-out test.

Implement a small inventory reconciler. It receives an initial stock and ordered
changes, validates each change, asks a checked audit callback to accept its typed
proposal, then commits the accepted result. A rejected audit must leave stock and
revision unchanged. A subsequent retry through the same live callback environment
must succeed. The application must report both the decision and final stock.

Required external behavior:

- Each inventory has an exact key, signed quantity and signed unit cost. Quantities
  and costs are nonnegative; arithmetic overflow is a checked error. A stock change
  names its key, signed delta and expected revision. Unknown keys, stale revisions
  and a resulting negative quantity fail without changing any inventory.
- Successful changes increment that inventory's revision once. The audit receives
  a copied proposal record containing the key, previous and proposed quantities,
  proposed revision and total value. It returns a typed receipt with a sequence
  and an accepted-value field. The provider checks that receipt before committing.
- A deliberately injected audit error propagates across the native boundary as a
  nominal checked error. Retrying the same valid change through the same callback
  environment succeeds. Invalid changes do not invoke the audit.
- Report decisions in input order, then final inventories in key order. Output
  records use ASCII TSV, with decimal integers and one LF per record. The recipe
  records the exact field schema before coding output, and an independent Python
  reference computes the expected quantities, revisions, audit sequences and
  values from inputs rather than copying Astra observations.

Use at least two inventories and twenty changes, including positive and negative
deltas, zero, stale/unknown/overdraw errors and an injected audit failure/retry.
Exercise at least two different valid input sets and a renamed/reordered variant.
There may be a declared signed-32-bit application limit with checked overflow;
silently wrapping is invalid. No fixed input strings or expected result constants
may participate in library or compiler admission.

The state abstraction must have multiple independent fields and type parameters,
including copied key/value information and an independently owned audit/context
object, with additional revision bookkeeping. It must use a different declaration
and algorithm from the indexer's owning slots, word buckets and file cache.
Use independent class and method type substitution where it serves reconciliation.
The checked callback uses a non-scalar record input/result. Ownership, cleanup,
failure and retry remain observable under actual memory checking.

Compile the reusable implementation as an opaque native library and compile its
consumer after hiding task-owned producer source copies. Exercise O0/O1/O2 and
mixed O0/O2 producer/consumer levels, with unsuppressed Valgrind and exact cleanup.
No C/Python implementation of reconciliation may substitute for the Astra work.

Freeze these requirements in Git before challenge integration. Retain minimized
failures. Fix shared compiler defects rather than changing valid requirements or
algorithms to match an incidental recognized shape. Any necessary requirement
amendment must be recorded explicitly and must not be described as an unseen
challenge result.
