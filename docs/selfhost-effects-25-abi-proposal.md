# EFFECTS-25 bounded recoverable-effect proposal, revision 1

Decision: **APPROVAL REQUIRED**. Launch authorization is not ABI approval.
No representation described below has been implemented in the self-hosted
compiler. The recommendation is alternative A, identified as **E25-A-v1**.
Approval authorizes implementation and qualification, not a passing milestone.

## Existing authority and fresh independent evidence

C0 is the unchanged LLVM23 production compiler, SHA-256
`e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b`.
Its source contract is [native exceptions](abi/native-exceptions.md),
[language exceptions](language/exceptions.md) and [ADR 0090](decisions/0090-native-exceptions.md).
The implementation independently retains declaration and exception contracts in
`bootstrap/core/core-exceptions.vala`, `bootstrap/cfg/cfg-exceptions.vala`,
`bootstrap/nabi/native-model.vala` (`NativeExceptionPlan`,
`has_exception_success_slot`), `bootstrap/nabi/native-builder.vala`,
`bootstrap/backend/llvm/llvm-type-mapper.vala` (`boundary_result_type`,
`signature`) and `bootstrap/backend/llvm/llvm-function-lowering.vala`
(success publication, checked calls, exception returns). LLVM uses fastcc in
`bootstrap/backend/llvm/llvm-lowering.vala`.

Fresh read-only evidence is produced by `tests/selfhost-effects/c0.py` in
`runtime/effects25/c0-design-v2/`: unchanged `tests/error-1/fixtures/heap-factories.astra`,
`argument-abort.astra` and `success-groups.astra` each execute at O0 and O2,
return 42, pass llvm-as/opt verification and unsuppressed Valgrind with zero
errors and zero live allocations. These six runs qualify design observations
about C0 only. They do not qualify self-hosted effects. O2 can inline a private
entry or specialize its return; the O0 definitions retain the original ABI.
The earlier observer attempt is preserved, including its overly strict
O2 attribute assertion; native execution and memory did not fail there.

The heap-factories O0 LLVM contains
`define internal fastcc ptr @astra.fn.0(ptr %success.storage, i1 %p0)`.
It stores the result pointer only on successful return. A forwarding call has
separate success storage, tests its returned exception and loads the successful
owner only on the null edge. The Error object is `{ptr, ptr, {ptr, i32}}`:
class descriptor, original origin record, counted snapshot. This agrees with
the accepted offset observations in `tests/error-1/fixtures/observer.c`.
Independent target layout/call probes remain a mandatory implementation gate;
these source/IR observations alone are not physical ABI qualification.

The C0 `argument-abort` program establishes reservation semantics: evaluating
`consume(move data, fail())` leaves `data` live if the later argument fails;
the move commits only when the consuming call starts. Once the callee has
entered, its owned inputs belong to it on either return path. Existing tests
in `tests/error-1/exception-tests.vala` separately mutate bounds, exception
success dominance, nominal identity, reservation abort and ownership edges.
Rethrow and dynamic identity are specified by `fixtures/rethrow.astra` and
its independent observer; they are not claimed freshly rerun by the six tests.

`finally` is absent from the accepted Astra grammar. The fresh C0 syntax probe
`try { return 42; } finally { }` is refused with “try requires at least one
typed catch”. Cleanup is lexical RAII plus generated normal/error edges;
this proposal does not add finally syntax. Vala implementation finally blocks
are not evidence of Astra source support.

## Two feasible private transports

| Choice | Transport and costs | Compatibility |
|---|---|---|
| **A / E25-A-v1, recommended** | One nullable owned error pointer is the function result; complete caller-owned success storage for nonvoid results; explicit branch after a call. No success storage for void. | Matches C0 native-exceptions-v14 physical channels for the admitted subset, with exact fastcc signatures and target layout evidence. Ordinary nonthrowing signatures stay unchanged. |
| B | A tagged aggregate containing an error pointer and complete success carrier, with only the selected alternative initialized. No caller success pointer; potentially more result registers, copies and aggregate lowering. | Source compatible in a separately versioned private compilation domain. Requires generated A/B adapters for C0 binary calls, additional layout and inactive-member proofs, and a second calling policy. Not recommended for this campaign. |

Both alternatives require explicit effect/cleanup control flow and original
error identity. Neither uses a global pending slot, errno, C++ EH, an Itanium
unwinder, traps in place of recoverable errors, or public C exception transport.
Adopting C0's already documented layout in a different compiler is still a new
self-hosted calling policy and therefore requires this decision.

## E25-A-v1 exact domain and machine obligations

Initial target: GNU/Linux x86-64 LP64, LLVM 23.1.4, one closed source set.
Only private direct native free functions and statically resolved existing
generic methods may gain `throws` transport. Preserve exact original symbols,
nominal Class identity, closed generic arguments and declaration-driven error
bounds. No type-parameter effect polymorphism, virtual checked calls, callbacks,
async suspension, foreign metadata, dynamic loading or cross-version linking.

Supported source constructs are declared `throws Error` (or a proved subtype),
direct/nested checked calls, `throw new E(...)`, `throw move error`, existing
ordered typed catches, bare lexical `throw;`, successful scalar/copyable record,
owned buffer and existing admitted heap Class returns, and normal returns and
loop exits crossing lexical cleanup. A Class result remains an exact nominal
owner; success does not grant permission to copy, borrow across cleanup or
ignore obligation 19. General unproved Class storage and constructors do not
become supported just because a factory returns their TypeId.

The exception domain is one source-nominated `[ExceptionRoot]` class with C0's
bounded readonly snapshot and get-only message property contract, plus finite
single-inheritance exception subclasses with independently checked base and
field layouts. Restrict diagnostic getters to accepted literal/readonly snapshot
reads; reject arbitrary helpers, effects, dispatch extensions and escaping
receiver views. Catch is a borrow of the separately owned error. A bare rethrow
transfers that owner, preserving the original allocation and origin record;
replacement must capture its input before retiring the caught owner.

For a free checked nonvoid function use fastcc `ptr(success*, source-groups...)`.
For an admitted static method the exact borrowed receiver precedes success
storage. Follow C0's leading sum/object-storage ordering if such a boundary is
later admitted; sums and legacy caller-backed object results are deliberately
excluded initially, so no guessed second result slot is introduced. Scalar,
record and buffer success storage has the already independently proved result
shape; an owned heap Class success slot contains one pointer. Void checked
functions return only the nullable error pointer. A nonnull result transfers
one live error owner and makes success storage unavailable. A null result means
all success components were initialized exactly once. Null is a valid empty
ordinary owner result, but throwing null retains the fatal invalid-use guard.

On this target the root layout is expected to be size 32/alignment 8: descriptor
at 0, origin at 8, snapshot data at 16 and i32 count at 24, including complete
tail padding. Derived classes embed the complete base, then declared fields
with target alignment. A descriptor carries exact parent, dynamic destroy
entry and slot table. Verify these numbers with independent C/C++ offsetof,
LLVM DataLayout and C0 object/native observations before admission. Do not
extend that header to existing unrelated Class layouts. Snapshot bytes retain
embedded NUL and exact UTF-8 count. Allocation failure remains fatal, without
an unwind promise.

Private symbols and retained plans identify the E25-A-v1/native-v14-compatible
policy, original declaration, concrete nominal arguments, result shape and
error bound. Nonthrowing functions retain their current policy and bytes where
applicable. No mixed policy call is emitted without an independently verified
adapter; no adapters to public C error propagation are in scope. Extra hidden
storage can change stack usage, register assignment and optimization. A checked
call adds a branch and possibly an alloca; nonthrowing calls gain no channel.
Inlining or promotion may remove storage only while preserving observable
effects, error identity, initialization and all cleanup paths.

## Ownership and stage-independent proof

Typecore first keeps declared success type/qualifiers separate from unsupported
effect admission. An inferred local denotes a conditional success value, not
an initialized owner on an error edge. Never manufacture an ID by name or
weaken `generic_type_matches`. Existing pending owner/borrow obligation 19 stays
pending until Flow independently proves it.

After approval Flow must represent ordered evaluation, reservations, call
entry, normal result definition and error continuation separately. Abort
uncommitted moves when argument evaluation fails. Retire entered-callee inputs
and its locals exactly once before propagating failure. Do not initialize the
caller's result/local on that edge. Previously live caller owners remain live
unless already consumed. Normal lexical exits retire live owners in validated
reverse order. Handler dispatch starts after protected-scope cleanup; handler
bodies target outer handlers rather than themselves or sibling catches.
Open error bounds require an ancestor catch or declared propagation; enumerating
known descendants does not exhaust an ancestor bound.

Core must retain exact source call/result/error and cleanup authorities. CFG
must reconstruct legal successors, cleanup order and handler scope. SSA must
verify result dominance only on success, phi predecessor identities, owner
versions, exception liveness, rethrow transfer and exactly-once retirement.
LLVM must independently bind the physical signature, argument order, success
stores/loads, nullable error test, branch, allocation/destruction and return.
Do not infer validity from builder caches or counts. Initial lowering disables
tail calls on checked paths; no tail-call optimization is permitted to skip
cleanup or invalidate caller-owned result storage. No new alias, capture or
unwind attributes are justified by a raw pointer or an effect flag.

Affected modules: `compiler/semantic/{elaborate,expressions,statements,checked,flow-*}.astra`
and focused new effect verifier/model files; `compiler/core`, `compiler/cfg`,
`compiler/ssa`, `compiler/backend/llvm` and their independent consumers,
plus `tests/selfhost-effects`, docs and explicit formatter classifications.
Generic verification retains independent nominal/reference/substitution
boundaries; the LLVM layout cache remains module-owned. C0/bootstrap and public
C ABI implementations remain unchanged.

Constructors must remain independently proved nonthrowing in this first
implementation, including error construction. Destructors/cleanup and error
message getters cannot throw. No double-error replacement during deinit,
foreign exception propagation, shared/weak errors, owning child-error graphs,
effect parameters or new finally syntax. Closed nested generics retain existing
resource/capability limits and require concrete type/receiver/effect proof;
unsupported complete source modules retain explicit deferrals.

## Acceptance and decision

Approval does not waive any gate in the submission. Require all 202 inherited
source identities per O0/O2 freshly compiled/executed; 12+ new programs/profile
(8+ actual error paths, 4+ success/owner controls); distinct source and ELF byte
counts; independent original-syntax and unchanged C0 oracles; Clang/GCC layout
and call probes; Typecore/Flow/Core/CFG/SSA/LLVM checks; actual ELF observations
and unsuppressed Valgrind on normal/error paths; 20+ substantive semantic
mutation categories and 6+ LLVM-valid physical alternatives/profile with valid
twins. Include wrong nominal owner, stale success value, wrong phi predecessor,
lost owner on failure, premature cleanup, swallowed error, incompatible catch,
double-retirement on rethrow and illegal public-ABI propagation.

Replay the exact four original populations under unchanged limits. Report their
next independent consumer result even if they remain rejected. A typed `graph`
or a later effect-6 frontier does not mean the complete `flow_index` executes.
Preserve historical status/proof records and the SSA stress, wide-u64/f32
Valgrind and complete Utf8Message factory deferrals unless independently proved.

User decision requested: **APPROVE THE BOUNDED DESIGN E25-A-v1**, **REVISE**, or
**DEFER**. Until that explicit decision, implementation may retain only
source-derived static type observations and pending obligations, plus read-only
observers and nonthrowing qualification. The campaign status remains PARTIAL /
APPROVAL_REQUIRED.
