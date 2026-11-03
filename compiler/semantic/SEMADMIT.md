# Source semantic admission

The opt-in `--admit` consumer uses `astra-flow/3`. It retains the original
CheckedIndex uses and whole-program fail-closed publication rule. `--flow`
and `--compat` retain `astra-flow/2` and `astra-flow/1` eligibility respectively.
This is an Astra semantic component compiled by Vala C0, before checked Core,
CFG/SSA, LLVM emission or bootstrap convergence.

The new slice covers concrete native nongeneric nested value records and
nonthrowing direct free-function record channels. Copy operations enumerate
the actual destination leaves and resolve each corresponding source leaf by
root, parent path and field SymbolId. Equal nominal types do not merge storage
paths. Each read requires live source storage and definite initialization.
Copying a scalar subtree adjacent to owned storage transfers no ownership.

Consuming record parameters and results derive their mode from the exact
declared recursive field graph, matching C0's implicit MOVE_VALUE contract.
Borrowed record parameters retain a separate nonowning mode. Direct calls use
the retained signature and original callee identity. Existing left-to-right
argument evaluation, owner reservations and call-duration loans remain in the
same source CFG. A reserve checks complete storage, with leaf retirement at
commit. Returning a borrowed record cannot manufacture an owner. Result leaves
are available only when all source functions, including the producing callee,
are admitted without an unsupported effect or semantic error.

Signature effect flags and dispatch are checked against the actual source
declaration, independently of the stored summary. A record-valued call requires
a bounded initialization, assignment, argument or return consumer; discarding
its result is rejected. Explicit owning-record release and readonly fields in
this slice retain unsupported policies and cannot publish a safe observation.

`COPY function block producer-node destination-root destination-field
source-field TypeId span` exposes the original producer and exact leaf paths.
Source-field zero denotes a checked move or direct result, rather than a
copyable leaf snapshot. `FIELD` supplies the root, parent, field declaration,
type and qualifiers. `CALL function block node callee SignatureId` binds a
commit to its checked direct signature. Existing `E`, `STATE`, `ACTIVE`,
`FIELD_STATE` and `PROOF` records retain their meanings. A displayed partial
state is not a proof. Public queries reconstruct and solve the source graph;
this guards corrupted model tables, independently of C0's enforcing checks.

Field writes check receiver storage and active root-dependent loans. Record
parameter storage stays read-only. Arbitrary methods and properties retain
named deferrals: a method named `read`, a getter or a body without an obvious
assignment is never a purity certificate. The corpus includes C0-admitted
mutating getters and methods, wrong receivers, read-only receiver negatives,
and nullable receiver behavior. Indirect, virtual, generic, foreign, fallible
and callback contracts remain outside this new slice. Explicit owning-member
extraction/replacement and arbitrary destructors also need their separate
per-leaf cleanup/effect contracts; supported C0 forms can still defer natively.

The original source corpus, C0 first diagnostics and prior native observations
must be frozen before campaign edits. Compare original node/reason/span tuples
on identical input bytes. New obligations and absent old rows are separate
from closed original obligations. Reproduction uses explicit external outputs:

```sh
python3 -B tests/selfhost-semadmit/qualify.py --compiler C0 \
  --build BUILD --runtime RUNTIME --baseline FROZEN
```

Without `--baseline`, qualification freezes a fresh comparison against the
unchanged legacy mode. This exercises the maintained contract; it is not a
replacement for a campaign's authenticated pre-edit observations. The bounded
next frontier is exact receiver/callee effect summaries and owning field
extraction/replacement, followed by independently checked Core IR and lowering.

The SEMADMIT-8 qualification has 38 cases: 17 admitted, 10 rejected and 11
deferred. O0/O2 observations match byte for byte. Eighteen substantive model,
source-authority and proof mutations reject at their owning checks. Independent
C0 checks retain exact first diagnostics; normally returning executable and
native-query cases pass unsuppressed Valgrind. A separate two-child destructor
witness verifies exact count and order through C0 while custom effects defer
natively. The original 50 FLOWSEM cases and 69 paired observations, 93 OWNFlow
expectations, 121 Typecore cases, 85 Binder cases, source/lexer/parser and focused
LLVM layout-cache checks retain their contracts.

The unchanged nested/deep repository fixtures become fully admitted. The frozen
matrix closes 82 matching original node/reason/span obligations, including nine
in those fixtures; nine new proofs and zero absent original rows are counted
separately. An exact pre-task syntax function slice also qualifies; its three
function obligations and one harness obligation have their own origin map and
ledger. Neither slice extraction nor changed deferral counts count as whole
compiler proofs. The immutable 1,503-graph/83,609-event/1,518-loan observation is
retained, and complete frozen/current compiler inventories still defer with
zero published whole-program proofs.

Qualification retained and fixed false admissions found by additional C0
boundary controls: discarded copied/owning results and explicit record release.
Readonly field policies and forged signature effects/dispatch have explicit
controls. Earlier builds and failures remain tied to their source hashes in
external evidence; they do not qualify the final implementation.

Compiled source inputs are committed at
`ca7a70b19375209d2f4c516cdd91670375ec688c`. The independent C0 binary is
SHA-256 `30865ad8a9d1652b63ad882f1e29031c76ac13204212f822b44235cb07df10de`.
Final cold component compilation took 349.24 s / 1,299,104 KiB at O0 and
680.35 s / 1,298,844 KiB at O2. Exact-product warm checks took 0.57/0.61 s.
These concurrent host measurements are costs, not a controlled speed comparison.
Failed, superseded and deliberately interrupted attempts have separate receipts.
