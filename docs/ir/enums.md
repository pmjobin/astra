# Bounded enum values and storage

Checked and Core enum producers represent construction, local snapshots and
native call results. Exact enum/variant/field tokens determine compatibility;
printed names and tag integers cannot substitute for identity. A constructor
retains a separate input correspondence record. A match owns a single producer
snapshot and complete arms with independently copied binding contracts. Pure
instance tokens associate selected fields with their intended snapshot.

CFG uses function-owned carrier slots, explicit construction/copy/parameter
acquisition and hidden call results. Match dispatch covers every declared tag and
has a distinct invalid-tag trap edge. Selected scalar and full record-leaf reads
initialize the exact binding destination. Nested enum bindings use complete
carrier copies. There is no ordinary writable enum projection.

SSA keeps these bounded memory carriers outside scalar promotion. Scalar payload
leaves retain the old SSA value rules. Function-owned projection contracts freeze
source slot, field, full record path, binding and result association. Scratch
slots have one producer; parameter storage has one acquisition. Each CFG/SSA
verifier independently builds read/write events and computes reachable must-
initialization over its actual edges, then rejects reads lacking initialization
on every incoming path. Active payload reads require an exact selecting dispatch
predecessor. Repeated fallback edges are split during LLVM lowering so PHIs use
the actual emitted predecessor.

Removing nominal definitions and owned-slot tables cannot erase the verification
obligation of remaining enum operations. CFG initialization checks inspect scalar
operand trees and return expressions, including tag reads embedded in a return.

Calls retain their original enum argument channels and caller result slot.
Returning an enum snapshots the value before ordinary lexical owner cleanup,
then copies into caller storage. Stack addresses do not escape as enum results.
All four established SSA verifier entry points and CALLABLE-1-R1's continuation
proofs remain present. Copyable enums gain direct generic value transport through their exact all-variant schema. Record-field and buffer-element admission remain separate authorities.

Retained-stage tests release syntax, Checked, Core, CFG, SSA and native function
graphs while the successor still verifies. Native sum plans retain pure immutable
identities and storage graphs; LLVM bindings retain those plans and LLVM handles,
without retaining upstream functions. Enum-bearing LLVM functions additionally freeze
the complete emitted operation order and actual predecessor edges. This rejects
well-typed copies moved before call/copy producers and publication before any
required field store. This immutable artifact boundary is checked before trusted
LLVM optimization; it is not a verifier for arbitrarily rewritten optimized IR. This proves the directed lifetime cases,
not arbitrary language memory safety. Qualification
records independent model, corrupted-output and memory checks.

ENUM-OWN-1 extends these same producers with COPY/MOVE/INSPECT authority. Core
reconstructs reservations and read-only arm roots. CFG captures owned arrays as
complete transfer tokens and verifies a unique dominating constructor consumer,
with no invalidation before commit. SSA uses the existing exact buffer pair
proof, rather than exposing owner components as ordinary scalar values.
Consuming arm projections associate the exact selected field with one new
owner; the retained-field mask prevents that field from also being dropped.

Both graph verifiers reconstruct owner acquisition, movement, active disposal
and inspection events. Reachable must-initialization, may-live ownership,
disposal and loan fixed points reject owner leaks, duplicate disposal, source
use after movement, invalidated inspection roots and surviving ended views.
Live flags implement conditional cleanup at joins; they do not replace these
proofs. The emitted owning functions freeze operands as well as instruction
order before trusted optimization. Full ENUM-OWN-1 qualification is partial;
see the implementation ledger for actual checks and missing coverage.
