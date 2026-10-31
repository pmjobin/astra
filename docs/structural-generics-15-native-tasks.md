# Opaque native task libraries

Native async declarations now call the producer's cold-task factory. Its frame
retains owned captures and points to producer-owned resume and destroy functions.
The consumer emits an external factory call and carries no replacement frame,
resume body or serialized implementation. Factory fastcc and resume/destroy C
conventions are independently checked against their exact symbols and signatures.

The native interface adds strict `task <callable-key>` groups with two fields:
`contract` records the runtime capability/provider, runtime error identity, typed
success/ownership, entry-point conventions and completion/error/cancellation
protocol; `frame` is a digest of the producer's verified private ABI/frame plans.
Only that digest crosses the boundary. The existing exact compiler, target,
layout, object and dependency receipts remain binding. Resume and destroy names
are derived from the recorded factory symbol with `_resume` and `_destroy`.

Imported signatures preserve their original async result, error and runtime
facts through Core, CFG and SSA. Detached native plans retain capture channels
and distinguish local task frames from imported factories. The completed ABI
must contain every local frame and no substitute imported frame. New proofs
reject a changed runtime after destroying each predecessor and reject lost
native task facts or a missing local frame after destroying SSA.

The three-layer witness transfers a Resource-owning generic Class into the
middle task, then into a leaf task that actually suspends and returns a generic
record. It observes completion, checked failure across both library boundaries,
cold cancellation and cancellation while a descendant timer is pending. Every
Resource is destroyed exactly once. Retry uses a fresh executor because the
existing consuming `run` operation also finishes shutdown; reusing the closed
executor was an invalid first witness, retained in its separate receipt.

Both separately linked virtual and real liburing profiles pass all eight mixed
O0/O2 combinations and O1 with exact event traces and nine memory runs each.
Real Linux execution completes three 100-ms timers, observes cancellation and
retires captures after provider users drain. The host's current setup/timer/
cancel probe also passes against liburing 2.15. The Linux witness checks actual
elapsed time and the leaf object's undefined Linux timer-helper reference.
The virtual consumer's file-open trace reads only its own Astra source plus
interfaces/objects and declared platform inputs. Producer implementation copies
are deleted before consumer compilation.

Controls reject erased async declarations, a different nominated provider,
malformed frame identity, a missing exported resume symbol, missing moves and
use after transfer. Rehashing metadata does not excuse those inconsistencies.

Compiler `f4ed5d3b76e85786b0394fd81ea46dac05f4e1779d1260c25bbd0a26182d9e07`
passes 110 source programs (1,871 checks, 330 memory runs), 200 negatives
(1,600 checks), 833 opaque-unit checks (186 memory runs), 211 structural proofs,
the expression matrix (168 checks, 24 memory runs), record equivalence variants
(18 checks, six memory runs), and real Linux task graphs (39 checks, nine memory
runs). Source, binary, recipe and receipt identities are in the accompanying JSON.
The registry contains 9,376 tests; final clean full G7 qualification is pending.

The first complete-program inventory check ran before the ABI builder added
frames. The builder now constructs them before its first verifier call, preserving
the strict inventory rule. The failed source/proof receipts and terminated first
unit run remain separate and receive no acceptance credit.

Native Map lookup is the next concrete gap: ordinary source checking succeeds,
while native export correctly refuses reliance on unrecorded callback effects.
Declarative effect/precondition and code-flow contracts remain work. Wider
ownership/callable families, the useful indexer, different application challenge,
final qualification and report are also outstanding. This increment changes no
historical expectations and claims no complete G3/G4 or milestone PASS.
