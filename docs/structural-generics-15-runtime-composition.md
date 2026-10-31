# Source runtime composition increment

The monolithic indexer exposed the program-wide singleton runtime nomination.
Two independently authored namespaces selected the same physical provider and
nominal error type, with different ordinary completion enums. Native-unit
composition already admitted these facades; combining their source declarations
failed before checking any task body.

Runtime nominations now resolve by source namespace, with the existing root
nomination available as a fallback. Each namespace has at most one nomination.
A source program requires one provider and one nominal runtime error identity.
Executor owners and completion enums remain nominal. Tasks can be awaited across
compatible facades; Core, CFG and SSA independently check provider/error
compatibility after their predecessor stages have been destroyed. This changes
neither the native module schema nor the physical task ABI.

The new fixture exercises copied generic record results, checked failure/retry,
and cold cancellation across namespaces at O0/O1/O2 with unsuppressed Valgrind.
Additional verifier controls reject provider and error-type conflicts. The
historical same-namespace duplicate-nomination negative remains unchanged; a new
source control also exercises that rejection. No historical expectation changed.

The initial authored fixture had a duplicate local name and an unjoined started
obligation on a potentially throwing operation. Its next version incorrectly
reused an executor after root completion, aborting in astra_async_run. Those
attempts and the debugger trace remain under runtime-composition-* in the task
runtime area. The corrected fixture uses one root lifecycle per executor.

Exact source/compiler identities and receipts are recorded in the adjacent
runtime-composition JSON. This is focused integration evidence. Full application
matrices, the frozen reconciliation challenge and final G7 qualification remain.
The reconciliation wire schema was also frozen before its output implementation
in tests/reconciliation-15/FORMAT.md; it does not yet claim an implemented tool.
