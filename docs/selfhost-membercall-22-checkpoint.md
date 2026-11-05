# MEMBERCALL-22 diagnostic checkpoint

Status: PARTIAL. Compiler, public ABI, C0, LLVM and resource-policy sources are
unchanged. This checkpoint does not implement the member-call repair or claim
source advancement. The next actual checked-source stops remain the four pinned
generic-inference diagnostics.

The exact 75,219-byte submission, SHA-256
`6418a8e3c44910443b6751778553e0a582b7f2d93e4e865b825ece311829874b`,
was accepted by the unchanged installed pm-next intake at
`eb2c16956d7b5b282e11b92fa8c3bbc2672e91c7`, tree
`6d23d48ad2024fdf321e974f298d75013fa83d57`. All 25 unique regular members
and all 24 indexed payload identities were verified. The exact predecessor is
preserved under `runtime/membercall22/predecessor-report.zip`, SHA-256
`30ad8111039c15ab7ddba118b9368bb4c574c3caf96e90186974d682a2e1a7ae`.
Its timestamped upload name corresponds to the local canonical report bytes.

## Separate call observations

The read-only `diagnose.astra` consumer is compiled against unchanged baseline
semantic sources. Its third build is the successful observer. IDs below belong
only to their respective frozen Binder/TypeTable universes.

| Population | Call node / span | Receiver symbol / nominal | Candidate method / callable | Explicit argument |
| --- | --- | --- | --- | --- |
| original | 40833 / [3243,3351) | 6540 / 181 | slot_for 2097 / 342 | nested call 40832, unavailable TypeId 0 |
| LLVM23-base | 42968 / [3243,3351) | 6659 / 182 | slot_for 2184 / 346 | nested call 42967, unavailable TypeId 0 |
| Class15-current | 46736 / [2690,2704) | 6896 / 186 | add 2309 / 361 | name 46735 -> local 9458, unavailable TypeId 0 |
| live-initial | 47584 / [2820,2834) | 6925 / 186 | add 2324 / 362 | name 47583 -> local 9516, unavailable TypeId 0 |

All four receivers have borrowed flag 2 and exact nominal Class kind 31. Both
method origins and their Class owners have zero type parameters. No concrete
callee is committed in `generic_calls` at these stops; the candidate method's
signature ID is zero, while its source callable type is recorded. The parameter
types are SymbolId (TypeId 54/55) and FlowEvent (TypeId 53), respectively. These
are nominal source records, not interchangeable layouts or erased pointers.

In the first pair, `checked_target` resolves to ordinary function 506/512 with
callable 1185/1196 and expected return SymbolId. Its third argument is an
unresolved receiver-place call to
`checked.bindings.program.arena.get_token_identifier(direct)`. The selected outer
method is concrete `slot_for(SymbolId)`, but `generic_select_call` still visits
its explicit arguments under the zero-type-parameter inference route.
`generic_unify` refuses TypeId 0; that is not evidence of a SymbolId conflict.

In the second pair, `bad` is already untyped before `graph.add(bad)`. Its
initializer depends on `argument`, whose earlier initializer is the unresolved
receiver-place call `checked.bindings.program.arena.node_at(arguments, i)`.
The same zero-type-parameter inference route compares FlowEvent with TypeId 0.
The complete upstream prefix facts are retained; a populated FlowEvent was not
observed at these stops. Post-error deferred-child traversal can overwrite use
facts, so those rows are not a time-ordered inference trace.

`trace.py` separately reads the actual machine operands immediately before the
unchanged observer's generic_unify call, with exact binary/disassembly binding.
All four observations have actual TypeId 0, type-argument count 0 and depth 0,
with the table's exact origin, receiver and parameter IDs. No checker operands
are changed. Product-specific debugging addresses are not admission rules.

The current `generic_method_target` immediately declines a nonzero
`receiver_place`. The five distinguishing controls isolate this missing path:
a known nested direct argument is admitted; wrong nominal and wrong arity
reject with C0 and Astra; C0 accepts a nested field-receiver call and an inferred
local derived from it, while the Astra checker reports unavailable generic
inference. Their observer output distinguishes an actual nonzero wrong nominal
type from the unavailable TypeId 0. No compiler spelling or source hash is used
as an implementation exception.

`reference.py` checks all four complete original FlowGraph Classes and records
with C0 in disclosed dependency views. For the first two populations it also
retains the complete original checked_target helper and exact nested call.
Later views check `graph.add(bad)` with the actual FlowEvent declaration.
`facts.py` separately compares the complete FlowGraph C0 ASTs against the
original populations and retains each complete original caller function AST,
source/node/span identity and bytes. These are C0 type/parser observations;
they are not native execution or complete original compiler/Class admission.

## Contract decision before complete original caller execution

Both required complete caller functions, `admit_record_value` and
`class_storage_slot_flow`, declare `throws Error` in every relevant frozen
population. The existing private native pipeline has no qualified throwing-call
result/cleanup contract for them. `flow_graph` independently defers signature
flag 64 as UNSUPPORTED_EFFECT, and the Core call verifier rejects that flag.

`effect.py` confirms this with paired parse-valid C0-accepted functions having
the same `return 7` body. The pure program is admitted; the throwing function
has a separate UNSUPPORTED_EFFECT refusal on its exact span. Exception-root
Class/member deferrals in that probe remain separately identified. A pure body
does not authorize silently dropping a declared effect.

TASK section 3 requires separate approval for a new general calling convention;
section 8 excludes a broad exception/factory extension. The complete original
caller requirement has therefore been preserved. No new exception contract or
weakened effect check was introduced. Scope clarification was requested: either
retain complete callers and this checkpoint, or explicitly accept complete
original callees and call shapes in new nonthrowing drivers while those callers
stay deferred. No broadened authorization is inferred from elapsed time.

## Verified continuity and unmet gates

All 172 inherited source-program identities per O0/O2 were freshly checked
through LLVM emission/verification and their exact qualified ELF products
executed. Every raw LLVM hash matches its predecessor. Distinct ELF bytes remain
172 at O0 and 152 at O2. Prior C0/ABI/memory qualification is reused only with
the exact sources/products/toolchain and remains historically attributed.

Both profiles freshly retain all 80 outcomes: 56 admitted, 12 rejected and 12
deferred. The module layout-cache lifetime valid/mutant/restored controls pass.
The preservation audit rechecks 451 protected files, 6,622 read-only donor
files and all 1,044 historical proof-output hashes. Historical proof bytes are
preserved, not freshly re-proven. Old statuses and accepted/rejected/expired
milestones are unchanged.

No new target native programs, new member-call mutation categories, new physical
alternatives or new normal-return memory qualification are credited. No
implementation, independent lowering qualification or frozen-source advancement
is claimed. G3-G8 are incomplete; G9 has continuity/preservation evidence but no
new O0/O2 native cold-build campaign. The exact two source failure shapes remain
the next source blockers. Whole compiler/Stage 1, exceptions/text factories and
the wide-u64/f32 Valgrind discrepancy remain deferred.

Failed attempts are retained: two observer assertions (an inappropriate generic
parameter query, then a zero receiver-token query); three rejected C0 support
views; an unrelated constructor-prefix deferral in the first distinguishing
fixture; unsupported `-O0 --check` CLI use; and a whole frozen C0 check timing
out at 300 seconds. The timer's child survived its timeout and was terminated
only after exact process/argv revalidation. Its CPU/RSS total is unavailable;
no whole frozen C0 success or complete cost measurement is claimed. Scoped C0
dependency checks are a separate successful result. Cold observer build costs,
fresh replay costs, logs and limitations are in the runtime audit.
The failed observer source and recipe versions were recovered by reversing the
documented edits and matching all four original pre-build SHA-256 identities.
The first debugger command-registration attempt produced no operand evidence;
only the successful command-file trace is credited.

## Resuming

Keep `runtime/membercall22/`, `build/membercall22/`, the original submission,
predecessor ZIP and current native intake intact. Do not reset or rebind the
submission base. Before publication, `intake.py --resume` rechecks this intake.
After a published checkpoint, do not clear its published flag: an explicitly
requested report amendment must use the installed amendment path and the actual
checkpoint report SHA, or a new engineering submission must pin the then-current
HEAD/tree. The recorded contract decision must precede any expanded effect ABI.

The bounded member repair still needs implementation: separate ordinary method
signature checking from actual generic inference; resolve exact receiver-place
member authority; preserve lexical types separately from independently verified
physical storage; and verify normalized receiver/argument order, loans and
source-instance identity at each existing consumer. Run the full new-program,
memory, mutation and four-population advancement campaign before any milestone
PASS. None of the diagnostic controls is a substitute for those gates.
