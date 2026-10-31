# Semantic optimization profiles

The compiler derives facts from checked, specialized SSA and verifies them
again before native and LLVM lowering. Ordinary code needs no optimizer
annotations. Strict arithmetic and deterministic cleanup still apply at O2.

| Domain | Eligible transformation | Boundary |
| --- | --- | --- |
| Scalar numerical function | Exact memory-free effect metadata | Checked traps, unknown calls and unproved memory access withhold it |
| Proved receiver or borrowed Class formal | Noncapture/readonly parameter facts | Volatile, foreign pointer exposure and unknown instructions fail closed |
| Independent exact local scalar-field Classes | Per-allocation heap removal to entry stack/scalars | Returned/moved/captured owners stay allocated; a safe neighbor can still promote |
| Exclusive promoted receiver | Callsite `noalias` | Ordinary borrowed views may overlap and receive no such claim |
| Immutable local scalar lazy metadata | Direct readonly factory body; dead cache state removal | Mutation, destructor, factory effects, errors, recursion and observers retain state |
| Proved local virtual receivers | Per-call exact nominal method/property target across helper and branch composition | Dynamic interface inputs and external implementations stay dynamic |
| Exact generic scalar method | Derived effects on the actual specialization | Templates supply no proof; native export additionally requires the admitted object proof |
| Fresh Shared count-one acquisition | Remove an unused balanced copy across scalar work, branches and proved scalar helpers | Used/field-based handles, weak/observer operations, callbacks and unknown counts retain effects |

These are finite domains. Resource aggregates, general closure environments,
async frames and arbitrary allocation elimination have no new promotion claim.
The ordinary ownership and native ABI verifiers remain in charge.

M18's current placement domain admits unrelated reference function parameters
beside a fresh candidate. Its actual uses must still prove no capture or publication;
incoming references do not alias a fresh allocation merely by sharing an activation.
Block parameters remain scalar/numeric-view in the placement domain. It admits
scalar fields and method receivers of separate local records, numeric arrays and separate default
numeric buffer owners. Views may overlap each other; allocation removal grants
them no alias or FP permission and preserves bounds/trap ordering. Context-owned
bytes, explicit buffer failure regions and selected/custom buffer allocators
remain conservative. Placement withholds facts for aggregate ownership storage, selected allocator contexts,
throwing receiver/constructor bodies and unproved instruction effects. Selected
checked callers can promote when both success and exception exits retain exact
cleanup. Candidate derivation tracks
each allocation's aliases forward. A separate consumer follows definitions
backward and checks construction and cleanup on every reachable control-flow path.
Returning or transferring one owner does not disqualify a separate local owner.

Exact dispatch derives finite allocation-origin sets for each receiver value.
It can consider multiple eligible local receivers and preserve their identity
across proved borrowed helpers and branch/scalar merges. A separate consumer walks
receiver definitions and CFG inputs backward, checks each allocation's capture and
cleanup obligations, and reconstructs the selected method/property from nominal
declarations and ancestry. A stored virtual-slot answer alone is insufficient.
Imported descriptors, mixed/unknown receiver origins, observable runtime policies
and unproved exposure retain dynamic dispatch. This does not add persistent borrowed
Class locals or promise specialization of arbitrary borrowed helper inputs.

Local effect consumers use a separate worklist of formal and memory obligations.
They follow current definitions backward to the actual receiver/parameter, inspect
every instruction and transitive callee, and check writes through possibly aliased
inputs. Unknown foreign calls can retain capture-only facts when no pointer is
exposed, but cannot supply readonly or memory-none facts. Initialization writes,
volatile accesses and checked traps retain their distinct effects. This consumer
does not call the producer's inference routine. Imported obligations require exact
checked native-object evidence, and declaration placeholders never supply facts.

Shared balance uses transparent regions containing scalar operations, local scalar
memory and direct scalar helpers with independently derived memory-free effects.
A separate forward state checker validates the fresh acquisition, unused clone
and balanced release. The proof does not infer termination through cyclic regions;
weak operations, unknown foreign callbacks and actual copy uses retain counting.
Checked calls and exits outside the balanced interval preserve their original
cleanup and do not disqualify the entire function. Checked calls, exceptional edges
and exits inside the interval still prevent elimination unless the exact balanced
release is proved on every path; the current transparent region does not admit them.
GNU native schema /6 transports the separately approved capture/read/memory channel.
Its consumer independently checks supplied object code before recomputing local
annotations and rebuilding native plans. Unsupported valid producers export unknown
facts. See [native units](native-units.md) for the admitted code and resource domain.

Inspect one source program with:

```sh
ASTRA_EXPLAIN_OPTIMIZATIONS=1 astrac --dump-ssa program.astra
ASTRA_TEST_OPTIMIZATIONS=off astrac -O2 program.astra -o baseline
ASTRA_TEST_OPTIMIZATIONS=on astrac -O2 program.astra -o selected
```

The test switch accepts exactly `on` or `off`. Without it, these optimizations
are enabled at O1/O2 and disabled at O0. Both binaries above use the same O2
LLVM pipeline and source policy. It is a reproducible ablation control, not
an unsafe permission switch. Setting it cannot make an unproved claim legal.
`ASTRA_TEST_VECTOR_MEMORY=native|scalar` remains a separate memory-lowering
control with the same bounds and alignment checks.

A93 observes 48,000 packet allocations with the pass disabled and zero with it
enabled, preserving early-return teardown and all output bytes. Its returned
owner variant keeps the allocations. A94 processes 48,000 samples into 375
metadata objects; readonly local metadata promotes, whereas mutation and an
observable factory keep the cache and allocations. A95 combines true runtime
interface selection, one closed exact call, an exact generic method, a retained
closure, Shared field borrowing and Weak expiration. A96 links independent
native units and processes four seconds at 48 kHz through FIR and biquads.

The [qualification recipe](../../tools/qualification/numerical-optimization-11.md)
records output files, independent C references, Valgrind, raw and optimized
LLVM, machine code, fixed inputs and repeated process/counter/compilation costs.
An unchanged executable is a neutral result even if short process timings vary.
No universal speedup follows from allocation removal. Promoted aggregate debug
locations are not promised; the selected existing scalar DWARF/GDB profile is
qualified separately. Historical LAZY-1 Q4 stays HELD/INCOMPLETE.

Implementation and proof boundaries are in
[ADR 0158](../decisions/0158-derived-effects-and-local-object-optimization.md).
