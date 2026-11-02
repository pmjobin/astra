# Native ownership flow

This component consumes the retained CheckedIndex → BindingIndex → SyntaxProgram
→ SourceSet chain. It is a bounded semantic analysis, not verified Core/CFG/SSA,
Stage 1, nonnull inference, an ABI proof or a replacement for production C0.
The frozen source contract is `tests/selfhost-ownflow/corpus.py`. C0 `--parse`,
`--check`, tooling observations, native compilation and execution are separate
observations. Only full checking supplies the C0 ownership oracle.

| Family | Supported domain | Remaining authority |
|---|---|---|
| Owners | numeric/bool owned buffers; exact native nongeneric Classes with empty zero-argument init and admitted producers | Resource import/cleanup metadata, generic owners, records, enums, shared/weak and owner slots |
| Producers | numeric/bool buffer allocation without allocation context or failure callback; direct nonthrowing owned result; default-heap simple Class construction and source-derived Class result/parameter origins | allocator contexts, fallible construction, aggregate completeness (20), arbitrary Class lifecycle/effects |
| Operations | initialize, read, local move, owned return/argument, release, buffer replacement/rearm, automatic scope exit | Class rebind (C0 rejects), Resource rearm/foreign cleanup, projected fields, buffer exchange |
| Flow | free functions, blocks, if/else, while/for, return, break/continue; structural zero-or-more loop fixpoint; ordered calls and short circuit | exceptions/reservation abort, async, callbacks, virtual/member effects, generic specialization |
| Loans | exact scalar typed-pointer addresses, pointer/object-reference local copies, null, raw borrowed noescape forwarding, direct borrowed call arguments | persistent borrow of owned buffer/Class (C0 rejects); projected owner fields, general returned borrow contracts, explicit borrowed POD-pointer admission (BORROW_CHANNEL_POLICY) |
| Provenance | local reads summarize at that exact local's region; source and backing are separate identities; call loans last through all arguments and commit | arbitrary aliasing receiver mutation, deep text, foreign capture, thread synchronization |
| Other proof boundaries | original TypeId/SignatureId and Binder edges retained | reason 18 nonnull facts and reason 20 aggregate completion remain separate |

OWNED=1, MOVED=2, RELEASED=4 are possibility sets. OUT_OF_SCOPE=8 is separate
bookkeeping; unreachable is bottom, not a slot state. Initialization is explicit.
Joins union reachable inputs. Reads require exactly OWNED; null may be OWNED.
Buffer replacement may dispose a live old value, as in C0; Class rebind is not
admitted. Scope cleanup retires conditional responsibility once. Calls reserve
consuming owners during left-to-right evaluation, protect all temporary loans,
and commit after every argument. Fallible paths remain deferred and have no
invented abort semantics. Fatal-trap execution is not an unwind proof.

The native checked-use adapter is opt-in for this consumer. Ordinary Typecore-5
observations keep their contract. A FlowIndex proof overlays individual reason-19
obligations only after graph validation, fixed point and diagnostic checks succeed;
the original checked uses remain available. Deferred functions never encode safe.

Initial C0 discoveries are retained in external `ownflow6/probes` and
`frozen-initial`: parameter assignment is forbidden; persistent owned Class aliases
are forbidden; ordinary loops conservatively retain both edges even for `false`;
active-local shadowing is forbidden. The corrected frozen contract predates the
native implementation. Sibling lexical names and equal names across functions
and sources remain exact distinct Binder storage identities.

The opt-in checked adapters retain typed move, allocation, address, index,
dereference and length uses. Ordinary Typecore-5 queries keep their earlier
contract. `flow-origins.astra` separately solves bounded source-derived Class
transport facts across exact local, parameter and result symbols. Its null and
heap facts are not ownership states. Unknown/lexical construction and unrooted
release/result obligations retain `CLASS_ORIGIN_POLICY` or
`CLASS_RELEASE_ORIGIN`; lexical Class construction is not qualified here.
Signed literal/constant buffer-count policy remains `BUFFER_COUNT_POLICY`.
Raw borrowed parameters cannot be stored or forwarded to unmanaged channels.

Graphs use explicit enter/init/exit events. UNINITIALIZED=16 is bookkeeping
separate from OUT_OF_SCOPE=8 and the 1/2/4 responsibility lattice. Ordinary source
locals require initializers; aggregate field completion remains reason 20.
Automatic retirement handles conditional responsibility and reverse declaration
order. The canonical source reconstruction rejects altered graph structure;
independent source/state assertions and full C0 checks qualify the builder's
rules. This is not a separate verified IR pipeline.

The internal observation starts with `astra-flow/1`. G/S/E/L rows identify
functions, slots, events and loans, STATE/ACTIVE expose fixed-point inputs,
ORIGIN exposes separate Class transport facts, and PROOF overlays exact original
reason-19 uses. DEFER retains a name, reason and source span. PARTIAL_STATE is an
unproved observation. `owner_at`/`loan_at` require the exact FlowIndex and matching
function IDs: -1 is an invalid owner/ordinal, -2 an unproved graph, and 0 bottom.
A positive fact never substitutes for checking diagnostics and proof status.

Limits are 8,192 functions, 262,144 symbols, 8,192 rows per function, 2,000,000
fact cells, 192 flow nesting levels, 1,000,000 event steps per solve and 8,000,000
Class-origin visits. Exhaustion emits FLOW_RESOURCE_EXHAUSTED and no proof.
The source/runtime receipts retain earlier failed fixture/implementation attempts.
