# 0086: Bounded internal generated continuations

Status: implemented for CALLABLE-1; see the validation report.

## Context and decision

R3's abstract contract/model does not emit native code. Existing direct source
calls have ordered scalar/record snapshots and distinct buffer-owner transport,
but no deferred descriptor or stable generated environment.

Add a compiler-only closed SSA continuation region with exact operation families,
typed captured operands, unique descriptor/environment authorities, and bounded
invocation/retention witnesses. Keep the contract LLVM-free. The
[representation map](../ir/internal-continuations.md) records the alternatives
considered before implementation. Source types, parsing, generic admission and
ABI profile numbers stay unchanged.

A family binds distinct step/cancel-drain identities to one exact environment
contract and a generated destroy identity. Its bodies receive value snapshots
and, optionally, an existing synchronous borrowed concrete int-buffer view.
They receive no descriptor, environment address or destruction authority. Native
plans independently own declared memory fields, signatures, roles and schedules;
their verifier checks flow separately from SSA. Backend correspondence rejects
locally valid substituted plans. LLVM bindings check physical selection,
publication, indirect-call channels and whole-descriptor moves.

Create reserves one descriptor/instance authority. Initialize installs complete
state and an optional zero-initialized buffer in stable fatal-allocation storage.
Publish selects an exact compatible step at runtime. Move transfers the whole
descriptor and disarms the source without relocating environment bytes. Begin/
call/end proves a non-reentrant interval; retain/release supplies separate bounded
use obligations. Destroy requires publication and retirement of all uses; it frees
the initialized buffer before the environment exactly once. Environment-free
controls consume their descriptor without allocation or a destructor call.

## Limits and future integration

The first region is sequential and closed on normal return. It introduces no
escaping source owner or callable CFG value. Later generated lowering can synthesize
regions at SSA and reuse the exact family/environment/native-plan seam. Cross-function
descriptor transport, executor CFGs and suspension live-slot maps remain ASYNC-1 work.

The local destruction context proves bounded compiler-owned use retirement, not
kernel quiescence. ASYNC-1 must connect additional retention to observed provider,
command and payload-release evidence, registration retirement and queued-reference
retirement. It must retain parent cancellation responsibility when a pending right
moves to a waiter. No mutable `safe_to_free` boolean replaces those obligations.

No runtime counters, atomic refcounts, queues, child trees, registration tables or
global registries are added. Foreign pointer forgery and arbitrary concurrent
reentry are outside this verified boundary. Sequential tests imply no thread-safety
guarantee. Fatal allocation retains existing non-unwinding behavior.

ADR 0085 remains Proposed. Q01–Q06 remain OPEN with Q06's minimum internal
realization qualified separately. Explicit approval of task/start/join syntax,
Completion/error propagation and suspension loans precedes source ASYNC-1.
The Linux/liburing profile remains proposed and unimplemented.

## CALLABLE-1-R1 verification completion

The R1 correction report records exact-baseline
reproduction of three independent-verification gaps. Detached continuation
signatures now reuse native channel/profile and group checks. Physical bindings
verify the entire descriptor projection and the expected environment allocation,
capture stores and publication order. Retained artifacts independently link
published carriers through whole-descriptor moves to their invocation sites.
These checks preserve the existing layout, allocator and normal emitted program;
they add no source syntax, scheduler or provider authority.
