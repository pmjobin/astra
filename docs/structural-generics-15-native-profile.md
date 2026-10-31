# Native model integration and structural transformation matrix

Full-target preparation exposed two standalone build dependencies. The neutral
callback input/effect contracts are now included centrally in `nabi_model_sources`;
they contain no semantic or upstream IR objects. Record-mode conversion belongs
to `NativeTypeMapper`, so its standalone users no longer depend on the SSA-level
`NativeAbiBuilder`. The builder retains a delegating entry point for its callers.

The bounded generality recipe applies nine transformation families, plus a
baseline, to two ordinary generic abstractions: a replaceable cell and an
accumulator with independent update bookkeeping. Seed 151065 determines inputs.
Both abstractions are changed for every family: declaration/field/method/module
renaming; copied fields before, between and after existing fields; an additional
owned field with distinct cleanup; reordered parameters with a third stored type;
nested copied generic records; helper extraction and a conditional; reordered
declarations and same-spelled namespace-private helpers; an actual native diamond;
and changed input sizes/values with an i64 substitution. Other mandatory owning
record, Class, Resource, buffer and callable payload families remain covered by
the existing source/unit/application recipes.

Each family runs inline at O0/O1/O2 and as an opaque L→M→C graph at O1. Factories
export their exact closed Class declarations; the middle library reads, updates
and retires their owners. Downstream commands import declaration artifacts and
native objects after producer paths are hidden. Python computes results and
reverse field/local retirement traces independently. The existing lifetime-only
Resource observer reports construction, domain-correct retirement and no survivors;
it implements no generic operation. All 142 checks and 40 unsuppressed Valgrind
runs pass on compiler e65bc72a7fb9e6727028f1be1170e4af982ecdb174b0871ff220ecc3f222e3a9.
This matrix does not replace the application's eight O0/O2 native link graphs.

The copied-field family found a real defect: a private i64 field could leave an
otherwise int/bool program at `scalar-ptr-v1`. Native declaration verification
correctly refused that field under the insufficient profile. Minimization showed
int and bool additions passed, i64 alone failed, and a separate i64 function
signature made the same field pass at `scalar-int-v2`. Profile selection now folds
all declared Class field types through the existing shared type calculation,
including fields without accessors. No field names or fixture identities enter
the rule, and the independent physical verifier remains unchanged.

The original native standalone model then exposed an overstrict integration
requirement: freshly constructed physical functions had no bound source effect
summary, so even the original scalar model failed before its unrelated checks.
Such functions now start with a conservative immutable contract: no readonly
promise, no callback inputs and no supported callback guarantee. A real producer
still binds checked facts exactly once. New standalone mutations prove neither
default promises nor explicit checked promises can be forged, erased or rebound.
All old standalone cases and exact expected diagnostics remain unchanged.

Focused qualification passes all five registrations: native standalone (21
groups), resource ABI standalone, its no-LLVM linkage check, structural generic
proofs (244 groups) and type/origin proofs (14 groups). All 204 genuine structural
negative cases pass their 1,632 checks. Exact sources, compiler and receipt
identities are in the adjacent JSON. Failed setup attempts and the minimized
compiler failure are retained externally, including noncanonical export spelling,
unsupported private-method spelling and an out-of-range literal before i64 context.

Full target compilation, fresh final registry execution, final strict compiler,
application/staged reruns and delivery remain qualification work. All three
existing freestanding-allocation-12 QEMU boot registrations are explicitly
authorized by native user replies; this checkpoint does not claim execution.
Five separate historical-fixture requests remain unanswered. No historical
expectation was changed in this increment, and no G7 or milestone PASS is claimed.
