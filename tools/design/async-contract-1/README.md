# ASYNC-CONTRACT-1 lifecycle model

This deterministic Python standard-library model qualifies the
[proposed contract](../../../docs/architecture/async-contract.md). It is not an
Astra interpreter/runtime, Linux simulator or real completion provider.

From the project root, use a fresh retained output path:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/design/async-contract-1/qualify.py --output ~/Workspace/codex/work/astra/runtime/async-model/model-review.json
```

`model.py` holds immutable task/registration/event state and separate application,
executor and abstract-provider actions. `qualify.py` holds literal handwritten
trace oracles (not reruns of transitions to produce expectations), rejected-action
checks, independently expressed invariant mutation controls, a bounded BFS and
one explicit fair shutdown strategy from every reached state. R3 also runs a
parent-only conditional drain strategy from each live-parent state in the
parent/child domain, without closing the executor or manually cancelling children.
`regressions.py` adds independently expected scoped traces and corrupted evidence
controls. Run without `-O`:
assertions are qualification checks. A failed assertion is a failing run, and
partial runs do not write PASS evidence.

Prospective exploration domain: at most two tasks and one abstract owner each, two monotone
registration identities, one queued work entry, two completion records, sixteen
explored actions, one nonterminal repeated event, and two waits in directed
coverage. Seven seeds cover timer, repeated notification, late release, scoped
borrow, two immediate tasks, timer/runnable sibling and parent/child. The R3 unrelated-task directed fixture alone uses three tasks and three enrollment
slots; the broad explorer stays at two tasks, two enrollment slots and the same
queue/registration/depth bounds. Separate directed admission cases use one slot.
New await/cancel edges change parent/child counts, recorded in the R3 ledger.
Exploration caps each seed at 100,000 states. Unique states include all live
responsibilities; traces are not retained for every successful schedule. Each
directed case retains its literal event list and ownership counts.

Task execution (building/new/ready/running/registering/pending/joining/terminal/dead),
owner holder, cold/enrolled association, pending waiter right, observation count,
initialization/publication, scoped cancel request,
borrow backing, queue dirty bits and parent joins are independent facts. Provider
target completion, continuing event, buffer-release notification and cancel-command
acknowledgment are distinct events. A promised late release remains required even
after an error/canceled target result. A locally prepared unpublished intent can be
revoked; an accepted operation cannot. IDs never reuse in this domain. The token
table remains model-owned even after frames die; a deliberately stale numeric
event is looked up there and ignored without reading dead frame state.

| Abstract event | First selected Linux witness | Coverage boundary |
| --- | --- | --- |
| submit | accepted TIMEOUT/IMMEDIATE_ARG SQE after token installation | Shared-memory barriers/partial kernel execution not modeled |
| target | timer target CQE, normally -ETIME or -ECANCELED | Raw errno mapped in provider, not in Task semantics |
| cancel_op / ack | separate ASYNC_CANCEL command and its CQE | Ack does not imply target or payload quiescence |
| more | MORE continuing notification | Deferred-provider compatibility only |
| release | later NOTIF/reuse permission | Deferred zero-copy compatibility only; source delivery waits |
| drain / retire | decode evidence, release local references, retire table entry | Real kernel/device revocation not proved |
| pump / wake | executor queue turn / dirty latch | User messages and kernel events are distinct; no source thread model |

An event rejected at finite completion capacity remains externally producible
after a drain; the model does not mark it delivered or release its obligation.
Dirty tasks excluded by work capacity retain readiness. A continuously cooperative
task gets FIFO service alongside completion/cancel intake. The fair-shutdown
check supplies eventual external events and continues pump/drain; it proves a
finite closing witness for each reached state under that strategy, not termination
for every infinite fair schedule. A provider that never releases backing can
prevent shutdown; no timeout authorizes free. User code that never yields is
outside this progress premise.

R3 `await_child` represents transfer of the consuming right before Terminal;
terminal `observe` completes transfer/discard, and child `destroy` ends the join.
Atomic bounded fan-out preserves a pending waiter when cancellation switches the
parent to Joining. Independent `missing_scoped_cancel` detects removed propagation.
Source publication/use requires observed target, release and applicable command
facts, retirement and no live queued references, independently of `access=False`.
Coupled target/release permission becomes observed on target drain, not send.
A rejected New enrollment preserves model state; source consuming failure refines
that rejection plus synchronous New disposal and Error delivery. The model fixes
one explicit executor and cannot prove cross-executor admission or allocator code.

Negative controls directly corrupt states rather than relying on transition
guards: premature frame/owner/backing release, cancel-ack quiescence, fake token
retirement, lost result publication, duplicate consumption/disposal, stale queue
frame access, dropped pressure wake, consumer write while externally retained
and queued-token retirement. Valid late identity replay remains independently
covered. Fatal termination has no further normal steps and no unwind promise.

Partial construction has one captured owner here, not all native field layouts.
The borrowed backing flag assumes admission; it does not prove compiler alias
analysis. The model's provider access conservatively includes the frame owner;
the selected immediate timer itself holds no payload pointer. Owned-error cases
test future compatibility, not a selected source error-object implementation.
Frame-local access witnesses stable storage, not emitted pointer arithmetic.
Generation wrap, arbitrary registration reuse, signals, true threads, allocator
failures, kernel memory models and network packets are outside the model.

The campaign-only delivery validators are retired. Run the model qualification
and its regression controls directly; the bounded scope above remains unchanged.
Historical campaign evidence is recoverable through Git history.
