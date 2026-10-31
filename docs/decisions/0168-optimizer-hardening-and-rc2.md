# ADR 0168: optimizer proofs, bounded tools and developer RC2

Status: resource policy and RC2 name approved by the user on 2026-10-29.
The concrete GNU schema /6 proposal was separately approved on 2026-10-29.
Compatible investigation and repairs proceed under M18; no gate passes by approval.

The concrete native summary proposal
specifies the approved schema /6 compatibility and independent object-checking decision.
Base: `34355ed7250e562cb323006782bdc13bf658f06d`, submission
`ASTRA-OPTIMIZER-HARDENING-RC2-18`.

## Proof and compatibility contract

Derive escape/alias/effect facts per allocation, keeping distinct allocation roots,
control-flow uses, cleanup and exception channels, allocator provenance and exact
nominal identity. One escaping root does not invalidate unrelated roots. Unknown
instructions, foreign effects, weak/concurrent publication, suspension, observable
identity and custom allocator effects remain conservative. Preserve constructor,
destructor and checked failure order. Entry stack placement must have a finite
static inventory; loops cannot grow it dynamically. No global heap fallback.

Reconstruct consumed validity from the actual typed program at each independent
stage. Re-running the producer's answer alone is insufficient. Imported summaries
must carry a version, nominal/signature/object identity, capture/effect/root facts
and invalidation dependencies; reject incompatible/forged claims before execution.
An opaque producer must remain source-hidden. An unknown foreign annotation is
never an Astra proof. Serialized optimizer authority is restricted to the separately
approved GNU /6 proposal linked above; unspecified metadata has no authority.
Existing native ABI, ownership and logical/physical lifetime
versions remain unchanged by the compatible framing repair.

Strict FP, checked traps, explicit relaxed-policy boundaries, allocator callbacks,
weak/control identity, lazy first-success/failure-retry/recursion and concurrency
semantics remain in force. Grant only LLVM permissions supported by reconstructed
facts. Exact receiver facts may cross proved helpers/branches; dynamic interfaces
retain dynamic behavior. Shared balance must account for every path and observer.

## Proposed observable resource policy

Retain the existing 16 MiB protocol/compiler-output ceiling, 2 MiB individual
source/config limit, 128-source limit and 30-second compiler deadline. Enforce the
compiler ceiling live across stdout and stderr together; collect concurrently and
reap task-owned children on every exit. Exact-cap output is permitted. POSIX child
process groups are task-owned; non-POSIX teardown needs actual platform evidence.

Proposed new limits: 128 queued messages, 32 MiB queued wire bodies, 128 open
documents and 16 MiB aggregate open UTF-8 text. Workspace sources, VAPI and native
interface inputs together have a 32 MiB read budget; individual source/config
limits remain unchanged. Reserve/control cancellation separately: store IDs only
for queued/active requests, discard on completion, ignore unknown/late IDs, and
reject duplicate outstanding request IDs. No silent request drops. On queue
saturation, terminate the connection with an explicit bounded overload diagnostic;
this avoids blocking the cancellation reader behind a full work queue. Reject
ambiguous JSON keys, malformed Unicode and frames. A client with incomplete input
has a proposed 30-second progress deadline; blocked output has the same deadline.
These are new refusal semantics requiring approval before implementation.

Keep the existing lifetime 8 MiB and 65,536-equation ceilings. Strip at most one
logical wrapper and reject repeated framing before suffix parsing. Preserve valid
logical/physical canonical archives, exceptional channels and existing valid graph
depth. Adjacent graph work/edge ceilings require measured evidence and an explicit
addition here if they would reject an otherwise accepted valid graph.

## Release and qualification contract

Proposed name: `0.0.3-dev-rc.2`, Linux x86-64 developer compiler/runtime/SDK/docs with
explicit installed LLVM/GLib dependencies. This does not reduce current supported
Windows COM/import/export, GObject/GIR, Linux worker/io_uring or selected no-OS gates.
Two source-identical clean builds compare installed bytes and modes; deterministic
archives must install, relocate and rebuild from delivered source without producer
source access. No public upload, Git push/tag, RC1 replacement or 1.0 claim.

Keep all G0–G11 gates. Preserve failed freezes, historical LAZYQ4/Surge PARTIAL,
the M17 360-second timeout and isolated 302.70-second pass. Same-O2 selected-fact
ablation records allocation/retain/machine-code observations and honest neutral or
slower samples. Freeze production before selecting application B. Final corpus
and registry evidence must identify all current names and exact source identities.
No campaign-wide clock or larger historical test deadline is introduced here.

Host packages, VM access/start/snapshots and private topology/external peers need
separate narrow permission once concrete commands and fixtures are reviewable.
Unavailability blocks affected qualification; it cannot silently remove a gate.

## Primary implementation references

Actual intake tools: Python 3.14.8, LLVM 22.1.8, Vala 0.56.19, Meson 1.11.2.
These version observations are not execution qualification.

- [LLVM 22.1 reference](https://releases.llvm.org/22.1.0/docs/LangRef.html)
- [Python 3.14 subprocess](https://docs.python.org/3.14/library/subprocess.html)
- [Python 3.14 queues](https://docs.python.org/3.14/library/queue.html)
