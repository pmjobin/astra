# ADR 0121: lexical `for` loops and explicit steps

Status: implemented; Surge 7 qualification in progress.

`for (initializer; condition; step) { body }` accepts a local declaration,
assignment, or call in the initializer, a scalar bool condition, and an assignment
or call in the step. Each clause may be empty. An empty condition means true.
The initializer runs once in a lexical scope enclosing the condition, body, and
step. Its names disappear after the loop. Existing duplicate-name rules apply;
this feature does not introduce shadowing of an enclosing live binding.

Each iteration evaluates the condition, then the body, then the step. Body locals
are unavailable in the step. Normal completion and `continue` clean up body-local
owners before entering the step. `break`, return, and a propagated checked error
skip the step. Loop-initializer owners remain live through the condition and step,
and retire on every normal or checked exit from their surrounding loop scope.

The parser retains actual syntax nodes and spans. Assignment/call nodes in the
step have no semicolon; the loop owns its closing parenthesis. Checked and Core
loops carry a distinct optional step block, with an immutable indication that
the block is required. Independent Core verification rejects missing steps,
multiple step statements, and control transfers substituted for the step.
Monomorphization preserves this block and its lexical text-loan extent.

CFG lowering reserves a separate step entry. Body fallthrough and `continue`
target that entry; its normal continuation targets the condition header. Checked
step calls use ordinary exception propagation and cleanup. SSA, native ABI, and
LLVM consume existing verified scalar operations and control-flow edges, with no
new runtime helper or C ABI shape. Structured generic-owner and text-origin proofs
merge body continuation paths before the step, then form their backedges.

The dedicated `language-usability-7-for` tests execute nested loops, empty clauses,
continue/break/return, lexical object lifetimes, and checked failures at condition,
body, and step under public O0/O1/O2 and unsuppressed Valgrind. The separate
`language-usability-7-contracts` tests mutate, reject, and restore stage models.
The historical `tests/loopctrl/pipeline.vala` rejection of valid `for(;;)` was
replaced, with explicit user approval, by the malformed `for(;)` rejection.

This ADR does not close Surge 7 U1: bounded borrowed `foreach` is still required.
