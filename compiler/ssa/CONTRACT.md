# Typed SSA, version 1

`SsaProgram` owns its `CfgProgram -> CoreProgram -> FlowIndex -> CheckedIndex ->
BindingIndex -> SyntaxProgram -> SourceSet`. Its separate `SsaData` owns typed
function, block, instruction, edge, value, variable, ordinary-use and incoming-edge
argument tables. Append-only ordinals are meaningful only with that exact retained
program and function. Public queries check the full model and both owners before
returning copies. Sources are retained through owned `SourceSpan` results.

The admitted domain is exactly verified CFG's free functions, primitive values,
direct calls, concrete records/buffers and structured control flow. Generic,
async, foreign, exception, indirect-call and unknown effect policies retain their
upstream deferrals. This stage does not parse source again or call another compiler.

One SSA block/instruction/edge refines each existing CFG row. A copied typed
`CfgInstruction` retains its exact Core operation, type/qualifiers, source/token,
callee/signature, ordered argument modes, authoritative place and effect contract.
Opcodes 1–12 are values; 21/22 initialize/store, 28 observes a call statement,
40 is conditional release/disarm, 41 exits a region, 42/43 begin/end a loan,
and 44 is a path-exclusive write of a short-circuit result. The CFG contract
describes terms 1 jump, 2 boolean branch, 3 return and 4 unreachable normal exit.

Every CFG value producer has a distinct SSA definition. A promoted scalar store
also defines a copy version. A scalar load retains its source operation and reads
the current version. Only unqualified primitive root places with no children,
move, address, borrow or other observer are promoted. Fields, records, buffers,
borrowed places and ownership transitions remain explicit memory/effect operations.
Entry parameters have typed definitions, including unpromoted resource parameters.
Promoting a value does not authorize copying an owner or asserting `noalias`.

Variables identify the proven scalar places and non-SSA short-circuit slots. The
builder computes structural reachability, dominators, immediate dominators and
frontiers by bounded predecessor intersection. It computes variable liveness and
places block parameters at live joins, including loop headers. This intentionally
permits redundant parameters; minimal SSA and block fusion are future work. A
forward fixed point supplies reaching versions across single-predecessor chains.
Every block parameter has one input per exact incoming edge, ordered by edge ID.
Parallel edges retain separate identities. Backedge values occur on their edges,
after the source instruction. Dead incoming edges have input index zero; dead
ordinary uses likewise have zero, with no invented undefined SSA definition.
Unreachable instructions remain typed and inspectable but never define a live use.

The verifier first revalidates retained CFG, including its independent Core/Flow
proofs. It checks exact row/edge/effect correspondence, ordered operands, type and
source identities, unique definitions, entry parameters, promoted-place authority
and complete incoming-edge coverage. Its dominance relation comes from entry
reachability with each candidate vertex removed. It derives parents and frontiers
independently, then compares the builder's complete analysis. For variable reads
and incoming arguments it walks backwards to the nearest write, block parameter
or entry on every feasible structural path. A stale value that dominates a use
still fails. No builder verified flag or expected projection certifies safety.

The exact graph/instruction correspondence is also the effect-state refinement:
all paths execute the same ordered memory, loan, reservation, commit, arm/disarm
and guarded cleanup transitions as verified CFG/Core. Ownership is not represented
as an additional freely copyable phi token. Return/break/continue cleanup follows
its original taken edge. Fatal operations retain their ordinary fatal contract;
this stage introduces no unwinding, speculation or alias theorem.

`ssa_read_*`, `ssa_immediate_dominator`, `ssa_in_frontier`, `ssa_phi_input`,
`ssa_def_use_count` and `ssa_def_use_at` provide downstream queries with typed IDs.
The last enumerates ordinary uses; the count also includes edge uses, which are
queried through `ssa_phi_input`. The separate Astra `SsaWalk` traverses only
verified SSA tables, counts references and reachable definitions/block arguments,
and identifies incoming loop edges. Its live-value count means a reachable value
with at least one reference, not a machine register-liveness analysis.

The test component supports `--ssa`, `--ssa-walk`, `--ssa-retain`,
`--ssa-cross-owner`, `--mutate-ssa`, `--ssa-graphs`, and `--ssa-forge-input`.
The predecessor CLI implementation is preserved verbatim as a separately named
test entry so `--admit`, `--core` and `--cfg` retain their previous bytes/statuses.
Production stage code does not depend on that test adapter.

`astra-ssa/1` is a deterministic internal diagnostic projection, not a stable file
ABI. It embeds the retained `astra-cfg/1` authority followed by `SSA_*` tables and
`DEF_USE` counts. Value kinds are 1 instruction, 2 entry parameter, 3 block argument;
variable kinds are 1 short-circuit slot, 2 scalar place; use kinds are 1/2 operand,
3 ordered argument, 4 promoted read, 5 terminator. Public output validates the
complete model first and accumulates bounded output before printing anything.

Each arena is capped at 65,536 rows, the dominance graph at 1,024 vertices, and
each dense variable/graph matrix at 1,048,576 cells. Construction and verification
each have 8,000,000 work units, with conservative setup-scan reservations and
metered graph/dataflow worklists. There is no recursive SSA graph traversal.
Output is capped at 16 MiB. `--ssa-limit`, `--ssa-work-limit`, and
`--ssa-output-limit N` only lower their respective caps and reject malformed or
overflowing decimal limits. Exit 1 is `INVALID_SSA`, 2
`SSA_RESOURCE_EXHAUSTED`, 3 `SSA_DEFERRED`, 4 `INVALID_VERIFIED_CFG`.
Failures emit no partial public SSA. Upstream depth failures are labelled upstream.

Build with `tests/selfhost-ssa/build.py --compiler C0 --build EXTERNAL_BUILD
--runtime EXTERNAL_RUNTIME`. The portable `qualify.py` uses the same arguments
and accepts explicit `--predecessor` frozen CFG-10 inputs and `--cfg` products;
its defaults are the preserved project exchange paths. Meson registers only the
focused `selfhost-ssa` test and `ssa-component-check` target. Source-backed
qualification, independent set-worklist oracles, C0 comparisons, mutations and
memory receipts are separate from the implementation.

C0's SSA may omit copy instructions and retain unused block arguments. Comparisons
normalize live incoming expressions and source symbols instead of ordinals or
dump strings. On skipped short-circuit edges, C0's canonical false/true and CFG's
copy of the guard are compared using that exact branch predicate. Native exact
edge/source/version checking remains independent of this normalization.

There is no LLVM emitter, machine execution through this new SSA, general memory
SSA, optimization/ABI change, full semantic admission or Stage-1 qualification.
