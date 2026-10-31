# ADR 0082: Allocation-site fatal failure actions

Status: accepted for ASTRA-ALLOC-FAIL-1. The numbered decision registry through
0081 was inspected before assigning 0082.

APP-CAD-1 established a specific missing boundary: a valid positive native-array
request traps on allocator null, while the original application's `cad_fail`
prints its diagnostic and exits 2. Its original path does not recover or unwind.
Intercepting a signal cannot distinguish this failure from bounds or numeric
traps. Application policy must be selected at the allocation site.

Add `new T[count] else failure_call(arguments)`. The action is an existing direct
named or supported member call with exact void result. Ordinary explicit generic
arguments and parentheses around the call retain their existing meaning. It is
not a fallback value, retry, exception handler, enclosing-function return or
promise that the callee never returns.

Count evaluation and validation happen once under existing rules. Empty ownership
remains null/zero with no allocator call. A positive representable allocation
publishes its initialized owner only on success. Only allocator null enters the
action. Its receiver and arguments then evaluate once in ordinary source order.
If the call returns, the allocation executes an actual trap before unreachable.
Negative counts, physical extent errors, count-expression traps and unrelated
bounds/numeric failures never invoke this action. Default new remains unchanged.

Checked/Core retain an optional typed ordinary call. A bounded CFG/SSA allocation
request has exclusive success publication and a terminal failure region. Lazy
argument effects are ordinary instructions in that region. This is preferable to
a backend annotation, which could not independently prove lazy evaluation or
branch-specific ownership. A general exception/result/nullable-owner mechanism
would exceed the fatal application requirement and is not selected here.

The terminal branch starts from the post-count ownership state. Explicit moves
and borrows obey ordinary call overlap and capture rules; its effects do not join
the success continuation. Replacement completes the incoming allocation before
compiler-generated disposal of the old owner. The old owner remains live at
action entry. Captured field receivers must remain valid. There is no caller
unwinding; ordinary callee cleanup of its own or consumed resources still applies.

Generic checking uses existing signature-derived element premises and exact
lexical type parameters. Materialization remaps the call, values, provenance and
source spans with the allocation. Failure text, count, diagnostic values and
destination types neither infer phantom T nor enter specialization keys. Caller
information identifies the written action call and arguments. No source reparse,
backend inference, closure object or dynamic propagation into library allocations
is introduced.

The existing NABI/CABI plans, direct calloc/free, structural zero, target layout,
checked extent and nobuiltin policy remain authoritative. Initial qualification
is hosted GNU LP64 x86-64 Linux. An action adds its own explicitly selected
dependencies; no default failure provider or new ABI profile is added. Foreign
code retains ordinary trust and side-effect limits, without invented noreturn,
purity, noalias or transitive allocation guarantees.

General recovery remains a separate design question. Deferred: try/catch,
Result/Option, nullable arrays, retry/fallback values, custom allocators, global
OOM handlers, nonreturn types/annotations, failure blocks, async, new text storage,
integer widths, ABI types, modules, targets, performance tuning and full CAD I
migration. See [language rules](../language/allocation-failure.md),
[IR proof boundaries](../ir/allocation-failure.md) and
qualification.
