# R5 continuation evidence

This is milestone 25 work in progress. Genuine unchanged original
`flow_number` has **zero Astra→LLVM→ELF executions** in this continuation.
The canonical report remains the previously published PARTIAL report, SHA-256
`16408c8bd00c3e81633e2ab7cefa6d557bbdad0dbdd9239add328c160fe7f887`.
No current-source PASS follows from the implementation or the checks below.

The continuation starts from commit
`0ce000667dd5cbee3e2af9fe0237b9c88a5536f3`, without resetting or repinning the
original R5 submission. The installed, unchanged `pm-next` amendment workflow
owns eventual publication. Separate continuation outputs are under
`work/astra/{build,runtime}/effects25-r5-resume`; earlier R5 evidence remains
read-only. Initial preservation and subsequent comparisons cover all 451
protected paths, 6,622 donor files, 1,044 historical proof hashes, C0,
workflow, settings, hooks and excluded scripts.

## Source and ownership implementation

The private effects path now retains original shared acquisition/clone/borrow
operations, actual source binder slots and field paths, Core responsibilities,
CFG commit/abort paths and SSA live intervals. Module-owned shared helpers
implement strong/weak control, overflow/fatal guards and payload destruction.
No artificial receiver binder or owner root is supplied.

Counted imported text calls retain their exact extern(C)/CCode declarations.
Caller file/line/expression operands derive from actual call spans and declared
parameters. The original parser-generated UTF8 factory body is checked against
its real declaration, buffer parameter, validator branch, snapshot constructor
and Error path. Its counted view remains a borrow of that parameter.

Integer division/remainder helpers guard zero and signed MIN/-1 without poison
flags. Short-circuit CFG/SSA lowering retains actual evaluation edges. New array
lowering retains backing slots, descriptor/index evaluation, bounds before an
indexed assignment RHS, fixed-array stack storage and scoped slice consumers.
The implementation includes casts, counted text length and nested property
receivers. These additions require actual integrated native qualification.

C0 permits slices of direct fixed-array locals; buffer slicing and subslicing
must not acquire execution authority. C0 also checks literal fixed-array bounds
at source checking time. The continuation preserves these distinctions.
Nested field exchange remains unadmitted until its complete capture and owner
path proof exists; the original builder exchanges its direct backing field.

The original allocator `noinline`, fatal allocation boundary, zero-buffer
behavior, libc memory-effect checks, public ABI and approved E25-A-v1 transport
are retained. Generic and SSA ceilings remain 256 and 8,000,000.

## Focused evidence so far

| Receipt | Actual observation | Limit |
| --- | --- | --- |
| `shared-stage-native7-O0`, `shared-source-source7` | All 12 shared sources pass Flow/Core/CFG/SSA and mutation twins; C0 O0/O2 execution and unsuppressed returning Valgrind pass | No Astra target emission |
| `frontier-source-source8` | All 14 focused sources pass Flow/Core/CFG/SSA, including the complete original builder/scalar-format inputs and actual InvalidUtf8 case; independent C0 O0/O2 execution and returning Valgrind pass | No Astra target emission |
| `shared-runtime-helper10` | 17 independently LLVM-valid shared-helper mutation categories; helper-only native destruction and memory differentials | Zero Astra pipeline credit |
| `utf8-runtime-helper3` | 18 independently LLVM-valid UTF8-helper mutation categories; complete scalar/byte/truncation/guard-page C0 differentials | Zero Astra pipeline credit |
| `integer-runtime-helper1` | 12 independently LLVM-valid integer-helper mutation categories; 8-bit pairs, wider boundaries/random cases, MIN/-1 and fatal zero | Zero Astra pipeline credit |
| `array-runtime-helper7` | 16 bounds and 8 cast LLVM-valid mutation categories, with positive twins; C0/native indexed-read and fixed-slice differentials, fatal bounds and returning Valgrind | Helper-only; cast controls are physical proof, not source execution |
| `array-oracles-source2` | Dynamic invalid fixed index traps before an observable RHS under C0 O0/O2 | Fatal receipts do not earn returning memory credit |
| `owner-form-oracles-source2` | C0 O0/O2 executes field-bearing derived Errors, computed/snapshot base messages, field receiver and explicit owner transfer | Derived Error lowering is still unfinished |
| `frontier-physical-oracle1-{O0,O2}` | New complete physical-test fixture executes under C0 with unsuppressed returning memory | Its Astra execution and 14 whole-module alternatives remain unqualified |
| `full-build-frontiercore1-O0`, `full-build-snapshotcore1-O0` | Full compiler source, whole-module controls and new Error snapshot helpers pass C0 Core checking | No native compiler or target qualification |
| `array-source-negative-oracle2-{O0,O2}` | C0 rejects all 15 source cases, including escaping views, moved roots and aliasing RHS | Astra rejection remains to be measured |
| `error-snapshot-helper1` | Ten independently LLVM-valid mutation categories; four helper-only ELF profiles match unchanged C0 constructor IR for exact bytes/allocation shapes, zero-count no allocation and forced allocation ordinal/size failures; returning Valgrind passes | Zero Astra source pipeline credit |
| `error-lifetime-oracle1-{O0,O2}` | Actual C0 source empty/single/NUL Error messages, derived literal and original InvalidUtf8 paths have complete allocation/free/fatal-size and returning memory observations | No Astra comparison yet |

Native4 is bound to its captured source witnesses. Its actual cold compilation
used 1,139.09 seconds wall, 1,130.00 seconds user CPU, 0.94 seconds system CPU
and 1,466,400 KiB peak RSS. All stopped, failed, superseded and warm/cold
receipts remain available; overlapping command durations must not be summed
and presented as elapsed wall time.

## Latest measured original frontiers

Native6 passes Typecore/Flow/Core/CFG over the full unchanged original
population, then stops in SSA. Read-only GDB diagnosis `ssa-limit-native6b`
observes **1,606 actual CFG blocks** at the unchanged 1,024-block comparison.
The guard executes normally and the program still returns its original failure;
no register, memory, branch or verification result is altered. The earlier
`ssa-limit-native6` receipt has an incorrectly labeled disassembly-command
field; the corrected b receipt retains the actual command and captured source
hashes. Its original bytes are retained.

The exact minimal byte/AST-preserving original dependency view independently
passes Flow/Core/CFG/SSA in `frontier-source-source8`. This is not full-original
SSA or compilation. All fourteen focused source cases pass the same stage
consumers at Native6, including the original complete builder/scalar-format
inputs. All twelve shared source cases remain valid.

The next source revision uses the existing verified 8,192-block CFG population
bound in SSA. Reachability, dominance and lifetime verification retain the same
8,000,000-step shared budget. Edge-coherent controls now update the CFG edge
table together with a forged continuation, so rejection tests the actual
source continuation rather than a stale edge table. `shared-stage-native7-O0`
compiled with frozen inputs and passed its identity check. In
`frontier-source-source8`, the **full unchanged original population passes
Flow/Core/CFG/SSA**, followed separately by the exact minimal view. All fourteen
focused sources and twelve shared sources also pass. No target has yet been
emitted by Astra. The next focused native build includes current LLVM lowering
and its independent consumers.

Native5 finished its C0 command but failed the existing postcompile source-hash
guard because task inputs changed during compilation. It has no product
identity sidecar and earns no qualification credit. Its stopped build, source
witnesses and read-only `stopped-stage-diagnose-stopped5` observations are
retained. Native6 was rebuilt with frozen inputs and passed the provenance
check. Future qualified builds must keep every recorded source/tool input
unchanged until that check completes.

C0 Error constructor IR also exposes a prior private snapshot mismatch: it
allocates exactly count bytes and skips allocation for zero count. The older
private helper added a trailing byte. New production snapshot/constructor
helpers correct this allocation behavior without changing the approved
32-byte Error header or transport. The original noinline allocation helper and
libc call/declaration memory checks remain intact. Its focused helper proof and
independent real-source C0 lifetime oracles pass; integrated Astra source
execution and fatal-size comparisons are still required. Historical R4 results
are not promoted or rewritten.

The full population and reduced view remain separate gates. Neither C0
execution, helper-only ELF execution nor a successful reduced view establishes
full-original compilation. Before final publication, rerun the retained 340 R4
native identities/profile, 101 semantic/52 LLVM-valid physical categories,
four exact cohorts and independent predicate 26. Historical R4 raw effect
identity drift remains 0/120, never byte-for-byte equivalence. Field-bearing
derived Error/computed base forms and all required original runtime/error/memory
observations remain acceptance obligations.
