# Generic owner locals and independently derived caller roots

Generic owned locals now use the ordinary ownership graph. Multiple inputs,
independent type parameters, transfer chains, branch locals, finite loop bodies,
forwarding and owning returns no longer depend on the old single-local and
terminal-consumer profile. `var` inference preserves a symbolic copied type or
an exact owned binding. Ownable capability requirements, nominal types,
structured liveness, loans and cleanup responsibilities remain binding.

Fresh exact typed owning calls acquire a local only after successful evaluation.
Core represents that acquisition explicitly and specializes each local's cleanup
from its actual origin equation. Optional old single-transfer annotations remain
compatibility metadata. They do not admit or reject the general graph.

Source detects escaping caller storage captured by a local. Core independently
reconstructs concrete callee and local equations. CFG reconstructs them from
calls, captures, acquisitions and transfers; SSA reconstructs them from actual
parameters, definitions, calls and edge arguments. No preceding-stage summary
supplies the proof. Direct calls compose actual input roots. Virtual calls and
opaque native declarations retain conservative declared storage contracts.
Closed member bodies participate in projection while preserving declared heap
formal constraints. Null-only results retain independently derived null
provenance. A local allocation may move only into a destination covered by its
original backing extent; it cannot escape its frame.

Four execution witnesses and the preserved historical controls cover copied-record
inference, two distinct Resource
cleanup domains, heap and caller-backed Class inputs, fresh result chains,
null-producing members, recursive transfers, and exact destructor order. Three
new source negatives retain copy, duplicate transfer and local-frame escape
failures. Eight added structural proofs destroy the preceding representation,
mutate a callee or operand, remove an acquisition, forge a pointer identity, or
invalidate a destination's backing extent. One explicitly proves the formerly
rejected exact typed Core producer is now valid.
