# Local owning records — finite STRUCT-MOVE-1 scope

The completion successor supports synchronous nongeneric flat local structs with
independent nominal Resource owners and scalar companions. Complete named
initializers evaluate in written order. Successful fields acquire individual
obligations; checked failure retires only that prefix in reverse order. Whole
moves into fresh locals preserve values and acquisition order. Null in one owner
does not suppress another owner's retirement. Later checked effects and ordinary
try/catch retain exact lexical cleanup.

Resource-field access/extraction, addresses, retained borrows, nested/generic
owning records, Class/slice owned fields, methods/properties and owning
by-value/foreign/collection/async transport remain deferred. Scalar fields remain
readable/writable while the record is live. Existing moved-state diagnostics are
preserved.

From the real checkout, run `sh tests/struct-move-1/verify.sh focused`. The
`regressions` mode adds the finite nearby fence. Both use the established
`~/Workspace/codex/work/astra/build` with warnings as errors and Linux async
disabled. Ordinary native permissions apply to external outputs. Neither mode
runs a broad qualification, installs dependencies or uses retired workflow tools.

The native driver checks fourteen exact malloc/free traces through six public stages,
ordinary compiler execution, independent `opt`/`llc` O2 execution and available
unsuppressed Valgrind. It mutates generated external IR to omit or double one
cleanup on normal and exceptional edges and requires leak/double-release detection,
then reruns each intact positive. The checked witnesses also assert exception
message bytes, object destruction and moved/empty-owner behavior. Source negatives
pin diagnostics and expected exit 1 across public routes and native compilation,
with no executable emitted. Stage-contract TAP tests forge a copy, wrong cleanup, missing CFG/SSA
retirement, omitted move disposition, duplicate acquisition and forged pointer
retirement/transfer, restoring a
verified positive after each mutation. Nine additional controls independently
accept a checked Core initializer, reject a missing checked effect contract,
and reject four CFG/four SSA exception-edge mutations.
Available Clang adds one-time LLVM ASan instrumentation and a C ASan/UBSan
observer for seven checked positives and two exceptional mutation controls.
Unsuppressed Valgrind independently detects retained allocations in both omitted
release controls, including allocations reachable through the observer registry.

The first-slice results remain historical; current checked evidence is recorded
in the Q10B validation note.

`tests/own-field/negative.py` and `parse-tests.vala` migrate only their obsolete
single-Resource struct declaration rejection into positive coverage.
All other owned-field negatives retain their existing contract.

Six obsolete refusal cases were converted with explicit per-path user approval
to positive stage and public O0/O1/O2 compile/run controls. All other historical
negatives remain, plus a checked nested-owning-record refusal. Independent
multi-owner/order/rollback proofs live in `tests/owned-state-6`.
See completion evidence.
