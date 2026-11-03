# Checked Core, version 1

`CoreProgram` owns `FlowIndex -> CheckedIndex -> BindingIndex -> SyntaxProgram ->
SourceSet`. Types, symbols, signatures, tokens and spans retain those exact owners.
Core IDs also require their stage owner and function. There is no serialized-input
ABI. The structural projection is `astra-core/1`, an internal downstream contract.

Values and authoritative places have different tables. Places preserve slot roots,
recursive nominal field parents, declaration identities, type and qualifiers.
Ordered child edges evaluate once, left to right; kind 7 evaluates its right child
conditionally. Structured while nodes own break/continue targets. Buffer allocation
is a producer with the existing fatal-failure contract, without trap unwinding.
Records remain typed trees and source-bound copy/move/borrow producers.

The supported profile is complete admitted free-function programs with scalar
values, direct calls, concrete records, scalar buffer producers and structured
blocks/if/while/break/continue/return. Unsupported forms defer the entire program.
There is no subset-selection API or whole-compiler admission claim.

Exit plans preserve inside-out lexical scopes, reverse storage acquisition order,
and reverse record-leaf declaration order. Actions test the runtime owner arm and
disarm exactly once; Flow's joined owner state is evidence, not a runtime value.
Call loans retain exact source and commit endpoints. This is responsibility for
ordinary returns and scope exits; custom destructors, release/replacement, foreign
calls, exceptions, unknown member effects and other unsupported policies defer.
Ordinary mutable borrows imply no exclusivity. Nullness is separate from ownership.

The separate verifier must validate the complete model before reads, traversal or
projection. It reconstructs source structure, types, field trees, call contracts,
loan endpoints and cleanup plans from the retained authoritative stages. Builder
status and printed text are never safety authority. Invalid input, invalid Core,
resource exhaustion and semantic/profile deferral are distinct failures. Limits
bound tables, recursion and verifier work; failed queries print no partial Core.

## API and representation

Build the component with `tests/selfhost-coreir/build.py --compiler C0 --build
EXTERNAL_BUILD --runtime EXTERNAL_RUNTIME`. It uses the existing exact-product
builder, adding Core sources and a separate consumer. Meson registers
`selfhost-coreir` and `coreir-component-check`; the portable qualification entry
is `tests/selfhost-coreir/qualify.py` with the same three explicit paths.

`astra-core-O0/O2 --core FILE...` and `--verify-core FILE...` verify and consume
complete programs before returning the projection. `--core-limit N` exercises
exhaustion. Exit 1 is `INVALID_CORE`, 2 `CORE_RESOURCE_EXHAUSTED`, 3
`CORE_DEFERRED`, and 4 `INVALID_CHECKED_INPUT`; failures have no Core stdout.
`--admit` exposes the unchanged preceding `astra-flow/3` observation. The test
consumer also exercises cross-owner rejection and spans surviving Core teardown.

`CoreProgram` retains semantic authority and construction data as sibling owned
objects, as required by Astra's containing-object/owned-child borrow boundary.
`core_read_node`, `core_read_place`, `core_source_span` require the originating
program and a function-scoped ID. Returned rows are copies. Raw arena helpers
are construction/test internals; every public read/projection revalidates the
whole model. There is no cached `admitted=true` shortcut.

Projection records are `SOURCE`, `DECL`, `SIGNATURE`, `CHECKED`, `PROOF`,
`FUNCTION`, `PLACE`, `NODE`, `EDGE`, `EXIT`, `CLEANUP`, `LOAN`, `TYPE`, `TYPEARG`
and `WALK`. NODE records contain identity, kind, function, original checked-use
ID, TypeId/qualifiers, ordered children, place/callee/signature/loop target,
edge range and source span. EDGE labels preserve exact parameter/field symbols.
Place indices are one-based; edge and plan ranges are zero-based. EXIT witnesses
address retained Flow scope-exit blocks; a consumer follows their source control
edges inside-out, then runs the plan's ordered conditional responsibility actions.
A move's target is zero for immediate transfer or the exact call node for staged
argument commitment. Moving disarms all owned leaves of that root once.

Typed literal payloads retain exact source-token spelling (including a signed
integer literal's operator); scalar operations retain exact operator tokens and
TypeIds. Integer width/signedness and wrapping, strict floating behavior, and
fatal arithmetic/allocation checks remain the language contract. Numerical
literal decoding and machine emission are future lowering work. No source is
parsed again by Core. Resources bound each arena to at most 65,536 entries,
structural depth to 192, verifier node/place work to 8,000,000 and projection
output to 16 MiB; the preceding stages retain their independent limits.

C0 comparison maps functions/callees, returns, conditionals, loops, short-circuit
nodes, typed binary operators and record moves. C0's expanded record statements,
parameter acquisitions and snapshot adapters differ from this typed structured
model. Debug-text equality is never its verifier or a serialization certificate.
The separate CoreWalk traverses actual Core children and typed storage, counts
record subtree leaves and checks store/result agreement without walking syntax
or FlowEvents.

## COREIR-9 qualification

The implementation inputs are committed at `5cb9d5724726b200805ba21a483277a31c9052a8`.
C0 is SHA-256 `30865ad8a9d1652b63ad882f1e29031c76ac13204212f822b44235cb07df10de`.
The original 44-source campaign matrix admits 20 programs, rejects 12 and defers
12 at both profiles. Its 17 inherited admitted programs include the unchanged
nested/deep fixtures and nested owning-record/call corpus. Later independent
order/trap controls add three source-valid programs. The exact original syntax
function slice has a separate Git byte-range/provenance certificate; it does not
admit the full compiler. O0/O2 projections match byte for byte.

Twenty-two distinct produced-model mutations reject at both profiles: types,
function owner, equal-nominal roots, field parent, value/place confusion, callee,
borrow/consume mode, argument order, eager short-circuit RHS, missing/duplicate
cleanup, loan end, forged proof summary, branch successor, span, cycle, resource
limit, move-as-copy, cleanup order, loop target, readonly authority and invented
alias effect. Each begins with a verified real Core, reaches its validator,
restores the exact rows and verifies the restoration. Mutation and normal/error
query consumers run under unsuppressed Valgrind, including retained source spans.

Independent C0 O0/O2 executables preserve wrapping results, real record behavior
and the existing destructor count/order (2 / 21). Additional source-order controls
observe a buffer freed by the first argument before the second argument fatally
traps; this is an intentional runtime negative, without automatic unwinding.
The short-circuit trap witness normally returns without reaching a zero-divisor
RHS. C0 runtime evidence is distinct from execution of the new Core.

SEMADMIT's exact original absolute-path ledger matches its historical result:
82 closures, nine new proofs, zero absent identities, with the same 17/10/11
admitted/rejected/deferred split. Fresh observations retain FLOWSEM's 50 cases
and 69 paired controls, OWNFlow 93, Typecore 121, Binder 85, source/lexer/parser
and current LLVM layout-cache checks. The complete current compiler/library
source still defers with zero whole-program proofs and no Core stdout.

Cold component costs were 405.40 s / 1,325,468 KiB (O0) and 663.85 s /
1,325,448 KiB (O2), built concurrently. Exact warm reuse has separate receipts.
These are costs for this larger component, not a speed comparison with earlier
milestones. Raw commands, hashes, timings, memory, failure/backtrace and original
proof ledgers are external, immutable report evidence. Early compiler checks and
the first native owning-call token-accessor failure are retained; the source and
lexer replay setup failure was followed by their unchanged maintained runners.

The next bounded seam is Core to explicit CFG, preserving call commitment, loan
endpoints and conditional reverse-order cleanup, followed by scalar SSA. For,
index/dereference operations, text, classes/lifecycle, explicit release or owning
field replacement, unknown effects, generics, exceptions and foreign/indirect
calls remain deferred where not represented/proved. No Core evaluator, native
backend, whole-compiler admission or self-hosted astrac is claimed.
