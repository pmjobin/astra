# R5 continuation evidence

This is milestone 25 work in progress. Genuine unchanged original
`flow_number` executes through Astra→LLVM→ELF at **O0**, with the complete
original population, exit 42, C0-equivalent contents and unsuppressed clean
returning Valgrind in `native-frontiers-llvm2-O0`. O2 remains unproved.
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

The new `native-frontiers-oracle1-{O0,O2}` receipts independently execute
20 original callers at each profile: the full target and exact reduced view,
integer boundaries, empty and growing builder/snapshot behavior, original
SourceBuffer copy/location, shared SourceSpan methods, SourceDiagnostic and ten
real Error paths. All returning Valgrind observations are unsuppressed and
clean. `native-frontiers-oracle2-O0` additionally replays all sixteen prior
original UTF8/builder callers and five C0-valid owner/derived Error forms.
`owner-source-negative-oracle1-{O0,O2}` confirms all six C0-rejected owned
result/rvalue receiver forms remain source-policy negatives. None of these
C0 observations earns Astra execution credit.

The continuation retained runner names the entire unchanged 41-recipe R5
population (the original 39 plus two prefix recipes) and explicitly resolves
read-only R4 history, original witnesses and predecessor relocation baselines.
Its `routing1` check executes the unchanged C0 source-policy recipe. No filtered
run can establish complete retained coverage. The signed-literal recipe now
measures actual emission/execution or preservation of a real refusal; its old
receipts remain historical.

`costs-prellvm1` indexes 2,573 actual GNU-time records and 46 compiler/check
attempts. It distinguishes failed postcompile identity guards from completed
products and reports command interval union separately from overlapping/nested
duration sums. Native7 used 1,183.24 seconds wall, 1,174.15 seconds user CPU,
1.10 seconds system CPU and 1,535,852 KiB peak RSS. The focused LLVM build
`build-llvm1-O0` completed from frozen source revision `94b2d6f`, with all 162
recorded inputs byte-exact. Product SHA-256 is
`4fb04c4a9192c8f0d1c38fa7566942d207f1050b87b6f116187327931cfd0d58`.
Actual cold compilation used 2,002.01 seconds wall, 1,987.41 seconds user CPU,
1.26 seconds system CPU and 1,696,884 KiB peak RSS.

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
focused sources and twelve shared sources also pass. That stage-only receipt has zero target execution credit. The subsequent
focused LLVM compiler and executions are separately measured below.

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

`runtime-stages-runtime1` replays the exact C0-observed expanded
callers through the qualified Native7 consumers and mutation twins. The full
original, reduced view, integer boundaries, empty/growing builder, formatter
widths, SourceBuffer copy/location, SourceSpan and SourceDiagnostic callers
and all original UTF8 cases reached SSA. Three derived Error declarations
remain actual Flow stops. Stage success does not earn target execution credit.

The first original LLVM authenticity probe, `native-frontiers-llvm1-O0`,
stopped after successful emission and LLVM verification: the test incorrectly
assumed textual basic-block order was execution order. The corrected probe
walks actual CFG successors. `native-frontiers-llvm2-O0` then verifies both
real discarded bool callees, the actual receiver/value operands and caller
invocation, independently verifies/optimizes LLVM, links ELF and executes it.
Full originals execute first; the exact reduced view independently executes
second. Both return 42 with C0 agreement and clean unsuppressed memory. The
failed first probe retains its source/command/LLVM receipts and earns no ELF
execution credit.

`native-frontiers-llvm1focused-O0` executes 14 frontier and 12 shared programs,
plus two valid owner forms, with independent C0 and returning memory. Its final
assertion remains failed because all three derived Error forms still stop in
Flow. `error-lifetime-llvm1-O0` passes all five real source allocation/free and
fatal-size comparisons, including zero-count no-allocation and original
InvalidUtf8. Six owner-policy negatives are rejected by C0 and Astra.

`array-source-negative-llvm1-O0` fails: both literal end indices on one-element
fixed arrays were wrongly emitted, while C0 rejects them. The legacy decimal
helper's truncating `(limit - digit) / 10` check can return a digit above a
small limit; the new source-bound consumer omitted an explicit result range
postcondition. Runtime bounds remain guarded, but that cannot replace C0 source
rejection. This failure is retained. `recover_array_decimal` now checks the exact
nonnegative range after parsing. `array-bound-helper1` independently verifies
its complete source/AST against 759 integer cases under C0 O0/O2 with clean
unsuppressed memory. Actual repaired Astra source rejection remains to be
measured with the next compiler revision.

The task-owned full build recipe now has a finite 10,800-second deadline,
reflecting the larger source population and R4 O2's already measured
3,279-second cold build. This changes neither installed workflow nor a compiler
resource ceiling. No final matched integrated pair has been launched in this
continuation.

Derived Error completion must retain the observed C0 order: allocate the actual
derived payload, evaluate its real base initializer, initialize the parent
snapshot, then store own fields. The measured root header is 32 bytes and the
single-int derived payload is 40 bytes. A source-bound normalized receiver and
actual catch-owned SSA identity must carry field/method authority; merely
relaxing the old zero-field Error shape would not implement these operations.
The E25-A-v1 checked transport and public ABI remain unchanged. These are
outstanding implementation requirements, not qualifications.

The full population and reduced view remain separate gates. Neither C0
execution, helper-only ELF execution nor a successful reduced view establishes
full-original compilation. Before final publication, rerun the retained 340 R4
native identities/profile, 101 semantic/52 LLVM-valid physical categories,
four exact cohorts and independent predicate 26. Historical R4 raw effect
identity drift remains 0/120, never byte-for-byte equivalence. Field-bearing
derived Error/computed base forms and all required original runtime/error/memory
observations remain acceptance obligations.

`native-frontiers-llvm1runtime-O0` completes all eighteen expanded original
runtime callers and all sixteen retained original UTF8/builder callers through
actual Astra→LLVM→ELF, matching independent C0 and unsuppressed returning
memory. This includes original SourceBuffer/SourceSpan/SourceDiagnostic,
repeated growth and snapshots, INT_MIN/64-bit formatters, empty/ASCII/multibyte/
NUL and all eight retained malformed UTF8 cases. These are O0 observations;
none establishes the required O2 or final matched-source pair.

## Derived Error stage revision in progress

The source normalizer now retains actual Error constructor/method copies, their
real borrowed receiver declarations and checked base-expression syntax. A
separate Error layout plan preserves the approved 32-byte header and places
derived fields after their parent payload. Its independent consumer recomputes
parent/field offsets, symbols, flags and TypeOwner identity. Flow operations 65
(base snapshot initialization), 66 (actual catch borrow) and 67 (derived Error
construction) carry separate receiver/catch owner identities through Core/CFG/SSA.
Catch lookup is an independently verified symbol-to-catch map; outer catches
retain their actual owner instead of inheriting the innermost lexical owner.

`shared-stage-errorcore7-O0` passes current focused C0 Core checking, including
new source/field/CFG/SSA mutation controls. This is source checking only. A
new focused native stage consumer will test actual admission before the final
LLVM implementation and matched builds. LLVM emission/checking for these new
Error operations remains unfinished; no derived Error execution is claimed.

`error-order-oracles-source1` independently observes C0 O0/O2 argument effects
before object allocation, followed by base evaluation/snapshot and own-field
initialization. Forced object and message allocation failures stop the later
observable effects. The nested outer-catch witness is independently C0-valid;
its distinct outer/inner messages and scalar fields will check owner selection.
The generic solver algorithm, instance ceiling, public ABI and checked E25-A-v1
transport are unchanged. The generic consumer's closed receiver domain now
recognizes the separately qualified Error source family.

The LLVM revision now emits derived allocations at the checked Error payload
size, the dynamic descriptor and the actual normalized constructor call. Base
snapshot initialization uses a separate lazy module-owned helper; field access
selects the Error payload family, and derived destructors retire own fields
before the parent without freeing the object twice. Independent consumers
recompute physical offsets and check the actual constructor, receiver, descriptor,
catch phi, destructor and instruction inventories. Ordinary Class payload caches
remain separate. The allocator noinline and C memory-effect checks are retained.
These changes have passed focused C0 Core checking (`errorllvmcore2`) and full
C0 Core checking (`errorfullcore2`); the added ten physical mutation controls
also pass full C0 Core checking (`errorfullcore3`). These source checks earn
no derived Error native execution credit.

`error-snapshot-helper2` passes sixteen independently LLVM-valid mutation
categories with valid twins and four helper execution profiles. Its exact C0
constructor comparison also initializes preallocated derived storage, checking
descriptor/origin/tail canaries, empty/nonempty text and independent copied bytes.
`native-frontiers-errororacle2` confirms all six owner fixtures independently at
C0 O0/O2, including distinct outer/inner catch messages and receivers.
`error-order-native-oracle1` validates the new allocation/order differential
runner against fresh C0 O0/O2 executions; no Astra component was supplied.

The first LLVM Core preflight rejected an owned-child local alias; its failed
receipt remains, and the verifier now takes a real borrowed argument instead.
The first full Core preflight stopped before compilation because the historical
call diagnostic differed from the current verifier. The task-owned full build
recipe retains that historical diagnostic under a distinct witness name and lets
the existing GENREF generator derive its current read-only observer. It does not
alter a compiler predicate, installed workflow or historical evidence. The
focused native stage consumer remains the next actual admission check before
expensive matched native integration; O2 target execution remains unproved.

`shared-stage-errorstage1-O0` completes its native build with the frozen input
identity guard intact (wall 1,203.66 s, user CPU 1,195.26 s, system CPU 1.03 s,
peak RSS 1,519,920 KiB). `runtime-stages-errorstage1` independently confirms the
full original and separate minimal view through SSA. Both ordinary owner cases
and the root Error order case pass. All six derived Error attempts stop in the
Flow consumer, status 1 with boundary 0. Its leaf diagnostics identify the throw
statement, not the earlier derived declaration: the independent throw predicate
still admitted only legacy operation 5 and omitted source-bound operation 67.
The nested case also exposes a missing conditional boolean type fact when
short-circuiting two recovered `.message` comparisons. These failed receipts
earn no derived Error execution credit.

The corrected throw predicate recognizes the separate checked Error construction
family. The conditional-type refiner and independent consumer now require actual
boolean child facts and an actual `&&`/`||` AST token, without changing the
original CheckedIndex uses. A coherent forged type/Flow-row mutation checks the
new consumer. Constructor reservations now recognize operation 67 consistently
with the existing independent owner consumer. `shared-stage-errorcore8-O0`
passes focused C0 Core checking; the corrected native stage replay is pending.
