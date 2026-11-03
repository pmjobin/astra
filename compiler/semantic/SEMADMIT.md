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
