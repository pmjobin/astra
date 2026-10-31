# Historical compiler latency finding

ASTRA-COMPILE-PROFILE-1 measured revision
`ca7c2301c60f92185e1c8689b3d41f470ee92b0f`. Its measurement qualification passed;
no production optimization was implemented. On that study's ordinary compiler,
CAD P/I0/I1 compile/link medians were 271.987/533.103/495.324 ms. These are historical
observations, not current throughput measurements or a general scaling law.

Four independent SSA verification calls accounted for roughly 69% of the
instrumented native-state increase over P. A bounded Callgrind investigation
identified repeated borrowed-buffer interval checking as a candidate for study.
This does not authorize removing a verifier call: construction, NABI, CABI and
LLVM each own an independent boundary. Generic materialization was not supported
as the explanation by the selected equivalent-value controls.

The useful measurement discipline is retained: fix workloads before sampling;
compare ordinary, instrumented and recording-disabled compilers; preserve exact
stage/object/executable parity; reconcile monotonic timestamps per sample;
separate inclusive parents from exclusive children; retain outliers and failed
attempts. Compiler setup, C adapter translation, application execution, memory
instrumentation and archive work are separate quantities. Independently computed
medians need not sum to the median total. Wall intervals include scheduling and
waiting and are not CPU-linker attribution.

The pinned instrumentation and campaign-only replay/packaging tools are retired.
Their exact source, reports and original limitations are recoverable through
[Git history](../history/active-tree.md). Any new optimization needs current
paired measurements and unchanged independent verification, lifetime, negative
and emission observations.
