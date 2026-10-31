# ADR 0091: Deferred unique tasks with native exceptions

**Direction:** USER_APPROVED A2-NATIVE-EXCEPTION-TASKS, in the live ASYNC-1 conversation on 2026-10-08. The user expressly approved deferred unique tasks, ordinary await with native exceptions, separate propagating cancellation, explicit start/join obligations, the bounded suspension-loan/frame subset and an explicit virtual executor/root bridge. The approval also authorized one cumulative 21,600-second campaign under existing disk safeguards.

**Implementation:** R1 completes the bounded source subset and finite controls described in the [source guide](../language/async.md) and current validation scope. Exact full-suite and independent-regeneration outcomes belong to the external R1 delivery; the original PARTIAL record remains historical.

An async call evaluates arguments once in source order and creates a cold unique task. A compiler-generated heap frame owns captures and persistent state. Starting enrolls work on the explicit executor without executing the body inline. One consuming await delivers the success value or transfers the original native exception. Cancellation propagates on its separate path. `await cancel_and_join(move task)` explicitly drains and discards an outcome.

Starting creates a join obligation on every reachable normal and exception exit. A handler may suspend while draining a sibling, retain its borrowed exception/message view and rethrow the same exception. Cold tasks can move or drop. Published success, exception and cancellation are immutable. Retirement requires observed release, queue/timer quiescence, drained descendants and consumed observation authority.

The approved first executor uses virtual logical ticks and bounded manual pumping. One consuming void-root bridge returns the ordinary `Completed`/`Cancelled` status or transfers the original native exception. Manual shutdown preserves the root observation right until consumed. Real native Linux providers require the subsequent ASYNC-IO-1 gate.

The approved result scope includes void, copied scalar/record/enum values, owned primitive/record arrays and owning enums. The approved loan scope includes a sealed direct parent-local borrow. R1 represents their complete capture/storage/transfer groups and source correspondence. Its positive loan subset uses a fresh direct await of a sealed fixed parent-local array view, with backing retained through child/provider join.

The task sidecar uses the next supplemental capability, `native-tasks-v15`, beside existing synchronous profiles. Body identity, logical success ownership, callable channels, frame layout and runtime association remain separate verified facts. Actual LLVM bindings retain concrete identities after predecessor graphs are released.

[ADR 0085](0085-native-async-contract.md), the original R3 proposal and earlier explicit-outcome drafts remain historical. The current conflict map is in the source guide. [ADR 0090](0090-native-exceptions.md), ordinary Result/enum values and the accepted ERROR-1 reconstruction remain intact. General Class results, shared tasks, arbitrary task fields/parameters, broad loans, async methods/generics, arenas, cancellation recovery and nonvoid roots remain named extensions. LAZY-1 stays near-term; PERF-01 stays unscheduled.
