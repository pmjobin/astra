# Direct calls across compiler stages

[Generic calls](generics.md) retain an exact generic-definition target and ordered
semantic type arguments in checked/Core IR. Core specialization binds them to one
canonical concrete CoreFunction. Downstream calls are ordinary direct calls with
no runtime type arguments. Exact non-generic function/method/property targets
survive substitution, and all native callers share one instance registry.

Each body builder creates all output functions before lowering any body.
Native signature planning creates them all before validating calls:

| Boundary | Exact mapping | Completed call target |
| --- | --- | --- |
| Syntax → checked | Compilation-unit function lookup, once | FunctionSymbol |
| Checked → Core | FunctionSymbol → CoreFunction | CoreFunction |
| Core → CFG | CoreFunction → CfgFunction | CfgFunction |
| CFG → SSA | CfgFunction → SsaFunction | SsaFunction |
| SSA → native ABI sidecar | SsaFunction → NativeFunction | Temporary validation target only; no retained call edges |
| SSA + native ABI → LLVM | Ordinal-validated SSA/native identities → predeclared LLVM function | Exact LLVM callee with NativeSignature-derived function type |

Maps use direct object hash/equality and never traverse by hash order. No
downstream lookup uses names. Source arrays determine declaration order. Maps
die with their builder; completed stages retain only stage-owned function
authority and source provenance. Through SSA, shared semantic types remain;
NABI physicalizes them and retains no semantic type objects.

Programs strongly own functions; through SSA, functions own bodies. NABI
functions own signatures and no bodies. Calls through SSA store GLib
WeakRef references, so self/mutual recursion cannot form ownership cycles.
Reading a target temporarily retains the live callee or returns null after
expiration. Membership checks reject same-spelled foreign functions too.

## Checked and Core

CheckedCallExpression contains a non-owning FunctionSymbol target, ordered
checked expressions, and the target's non-void return type. CheckedCallStatement
permits void or discarded non-void results. The Core input boundary validates
callee membership, arguments, and value-result validity.

CoreCallValue and CoreCallStatement preserve these roles using CoreFunctions
and ordered CoreValues. Both retain source spans. Core verification checks
program membership, exact arguments, and non-void value result/type equality.
It inspects arguments without traversing callee bodies.

## Explicit CFG execution order

For `return pair(identity(1), identity(2));`:

```text
call identity(1) → A
call identity(2) → B
call pair(A, B) → C
return C
```

CfgCallInstruction has a non-owning exact target, ordered arguments, optional
CfgCallResultValue, and provenance. Non-void calls require one correctly typed
result even when source-discarded. Void calls have none. The result is a Value,
never storage, and has no instruction backlink.

Lowering visits prefix operands first, binary left before right, and arguments
first-to-last before appending their call. Remaining CFG expressions continue to use
value trees; effectful calls become instructions and exact result identities.
Initialize/Store/Return/ConditionalBranch consume results after definition.

Verifier tables establish one defining call per result. Uses require a later
position in that block or a definition on every incoming path. SHORTCIRCUIT-1
extends this rule so earlier argument results can cross a later expression
region; [expression control flow](expression-control-flow.md) describes the
availability check. Duplicate/invented definitions, use before definition,
RHS-only values escaping a join, and cross-function uses fail.
Call targets never become successors. Unreachable calls stay in disconnected
CFG blocks. The dumper numbers results in block/instruction array order; these
function-local labels are debug information, not binding authority.

## SSA and promotion

SsaCallInstruction owns ordered SsaValue arguments and optionally one
SsaInstructionResult, and weakly refers to an SsaFunction. The instruction base
allows no result for void calls; computations and non-void calls require one.
Void calls consume no value ID. Results remain unique even when unused.

The builder consumes CFG instruction order, emits remaining argument computations
before each call, and maps each exact CfgCallResultValue to the new SSA result.
It neither replays calls on use nor interprets results as Places. The dumper
preserves instruction order regardless of numeric IDs. Verification checks
signatures, result shapes, unique definitions/ordinals, and dominance of call
arguments and later result uses.

Calls cannot currently alias caller Places: no address-of, ref/out, pointer, or
capture channel exists. Existing scalar promotion applies without implying
purity. In [choose-call.ssa](../../tests/call/fixtures/choose-call.ssa), each arm
calls transform once and passes that exact result as an edge argument; the
join block parameter merges them and supplies Return.

The established reachable projection excludes
[unreachable calls](../../tests/call/fixtures/unreachable-call.cfg) from SSA
without changing CFG. SSA adds no call graph, inlining, optimization, ownership
operation, physical ABI, or LLVM representation.

## Regression evidence

[Forward calls](../../tests/call/fixtures/forward-call.ssa),
[self recursion](../../tests/call/fixtures/recursion.ssa), and
[mutual recursion](../../tests/call/fixtures/mutual-recursion.ssa) retain exact
identities after upstream destruction. Weak references watch reclamation of
functions, bodies/blocks, calls, results, and provenance. Standalone executables
compile each representation without upstream models.

[Binary order](../../tests/call/fixtures/ordered-calls.ssa) visibly preserves
left, right, addition, return. [Nested calls](../../tests/call/fixtures/nested-calls.ssa)
preserve both identities before pair. Additional goldens cover discarded
results, bool conditions, Places, and branches. SCALAR-1 adds boundary-valued
arguments/results and preserves exact 1,003-digit argument syntax while rejecting
its out-of-range magnitude during semantics, before downstream call construction.
AstraIntValue supplies argument numeric meaning independently of source spelling.

## Historical CALL-1 qualification

Validated on 2026-09-06 from accepted SSA-1 baseline
`ae9c0d857c05c2be20dab17a7968d420b19e2a12`:

```sh
CCACHE_DISABLE=1 meson setup build-call-1-final -Dwerror=true
CCACHE_DISABLE=1 meson compile -C build-call-1-final
CCACHE_DISABLE=1 meson test -C build-call-1-final --print-errorlogs
```

The fresh build passed all **535 Meson entries**, including **603 GLib
subtests**, with no warnings. All 240 generated-C compile commands retained
VALA_STRICT_C and -Werror. The standalone suites passed 5 Core, 7 CFG, and 40
SSA subtests, including 44 malformed call cases across those suites.

All 12 protected executables passed link-command and ldd/readelf/nm checks;
the separate LLVM smoke executable was rejected by the negative control.
Standalone compile inputs contained no upstream models or builders.

Seventeen Valgrind runs reported zero errors and zero definitely, indirectly,
or possibly lost bytes, without added suppressions. Runs included all pipeline
call tests, each complete standalone suite, self and mutual recursion through
semantics/Core/CFG/SSA dumps, and nested, join, discarded, huge, and unreachable
call checks. Thus recursion was tested as both a source-built representation
and a standalone object graph. No production or test dependencies were added.

Prior parser expectations that rejected all calls or rejected assignment-in-call
before argument parsing were updated to the new grammar; assignment expressions
remain invalid. An expired-callee regression exposed the raw-pointer behavior of
plain Vala weak fields and led to the GLib WeakRef representation above.

## SCALAR-1 scalar and ordering boundary

Direct calls retain exact signatures, weak targets, recursion, and left-to-right
argument order. Int arguments/results now have signed 32-bit semantics.
`identity(2147483647)` and `identity(-2147483648)` succeed; positive 2147483648
fails at semantic analysis. Bool remains distinct, without numeric conversion.

New zero-divisor traps expose a concrete deferred-tree defect: `pair(a / b,
effect())` previously reached SSA with the later call before division. CFG now
materializes the earlier potentially trapping tree with CfgEvaluateInstruction
before lowering that later argument. Binary operands receive the same treatment.
SSA lowers the evaluation at its ordered position and reuses its result. The
existing call target/result model, effects, Places, CFG edges, and SSA promotion
remain intact. See [ADR 0013](../decisions/0013-scalar-semantics.md).

Native planning and body lowering preserve signed 32-bit wrapping, truncating division,
zero-divisor traps and their order, INT_MIN/-1 = INT_MIN, and INT_MIN%-1 = 0.
Semantic width still does not define parameter registers, return registers,
stack layout, linkage, calling convention, LLVM types, or bool representation.

## NABI-1 physical compatibility boundary

NativeAbiBuilder verifies SSA, creates every native-internal function and
complete physical signature, then validates direct calls against its temporary
exact SsaFunction → NativeFunction map. No source-name lookup occurs. The
validator checks one-to-one declaration correspondence, source-order parameter
counts/types, optional result channels, and every SSA call's target, arguments,
and result. Int maps to I32, bool to B1, and void has no result. There is no
adaptation, widening, or hidden channel. An unused scalar result still exists.

Forward, self, and mutual calls use the same completed declaration set. Tests
also construct valid SSA with two identical debug names and signature shapes;
native identities remain distinct and mutual calls reach the exact opposite
function. Same-spelled foreign targets and incorrectly paired maps fail with
deterministic compiler-internal errors. NABI retains neither the map nor calls,
so it cannot create a recursive ownership graph or keep SSA/types alive.

The [native scalar v0 contract](../abi/native-scalar-v0.md) defines an unstable
compiler-owned physical sidecar, distinct from C ABI and machine convention.
It assigns no stable linker names, registers/stack locations, bool memory
layout, or LLVM types. Existing scalar/trap/effect ordering remains a body
lowering obligation; NABI does not duplicate SSA to express it.

## LLVM-1 direct calls

LLVM lowering reuses NativeAbiValidator after verifying SSA/NABI. Validated
function ordinal/order rebuilds correspondence without matching debug names.
All LLVM functions are declared before any body, with internal linkage,
fastcc, and backend-local `astra.fn.N` names. Calls use exact SsaFunction
identity maps and NativeSignature-derived i32/i1/void function types, applying
fastcc at the call site as well. Parameters map by ordinal. Void calls have no
mapped result; discarded scalar calls keep their instruction/result.

Forward, self, and mutual recursion verify structurally. Ordered-call IR shows
left call, right call, add, return. Nested calls show identity(1), identity(2),
then pair. Choose-call has one transform call in each arm, a join phi, and return
of that phi. A division between calls creates guarded trap/overflow/continuation
blocks at its stored SSA position; following calls originate in the continuation.
There is no backend argument reordering or source-tree evaluation.

Neither fastcc nor ordinal symbol spelling promises a stable ABI. The module
retains no upstream function graph, so recursive calls do not extend SSA/NABI
lifetimes. LLVM verification is mandatory and no optimization or generated-code
execution occurs. [LLVM scalar v0](../backend/llvm-scalar-v0.md) documents the
physical implementation and regression evidence.
