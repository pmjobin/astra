# Native interface declarations and dispatch

Native module headers now preserve the language's bodyless interface operations,
including their implicit virtual dispatch. Their generated base initializer keeps
its imported origin. The native Class shape pins the interface role separately
from its physical fields, slots and descriptor. A rehashed interface-to-Class
substitution with the old layout is rejected before emission.

Imported concrete implementations retain their original native signature instead
of being rechecked as executable source bodies. Producer implementations still
undergo the interface read-only effect check. Core, CFG and SSA independently
reject a changed parameter ownership contract after their predecessor has been
destroyed. Imported declarations retain the existing bodyless-IR checks.

The three-layer witness calls implementations supplied by two later libraries,
including the final consumer. A property returns a specialized copied record;
virtual calls and exact reverse cleanup are observed at runtime. All eight mixed
O0/O2 combinations and O1 pass with nine unsuppressed Valgrind runs. Producer
implementation copies are deleted before consumer compilation. Mutating source
implementations remain negative.

The first debug-enabled graph exposed synthetic placeholder locations from an
abstract interface body. Generated instructions now use the operation declaration
location, matching the existing treatment of generated factory code. The original
failure is retained in `native-interface-units-first.log`; the corrected graph
passes with debug info enabled throughout.

Compiler `de2fcd0a06e4fea266f5d8dcc64aa5890054356fe4402bc726770a74f7ba4cc5`
passes 109 source programs (1,854 checks, 327 memory runs), 199 negatives
(1,592 checks), 789 opaque-unit checks (177 memory runs), the expression matrix
(168 checks, 24 memory runs), and all 206 structural verifier proofs. Exact source,
recipe, binary and receipt identities are in the accompanying JSON evidence.
The affected registry and final G7 have not been rerun for this compiler.

The next valid suspending void async source control passes source checking but
native export refuses its declaration. A separate copied-record async result
loses its logical success identity during frame planning. Both reproductions are
retained; neither supplies native async acceptance evidence. Producer cold task
factories, resume/destroy contracts, cross-unit cancellation and wider source
async composition remain required work. Callback preconditions, the useful Astra
application, generality challenge and final G7/G8 remain outstanding. No historical
expectation, milestone status or canonical report is changed by this increment.
