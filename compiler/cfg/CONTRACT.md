# Explicit CFG, version 1

The internal `astra-cfg/1` projection describes a bounded component between
verified `astra-core/1` and future SSA. `CfgProgram` retains Core and its complete
source/type/semantic authority. CFG storage and Core are sibling owners. Every
public block, instruction, place, span, graph query and projection checks the
originating program, function and the complete model. Arena ordinals are not
portable identities. Append-only construction has no deletion/reuse generation.

This first form uses one ordered instruction per basic block. It deliberately
leaves block fusion to a later transformation. Each block has one jump, boolean
split, return or unreachable normal-exit terminator. Successor and predecessor
rows are reciprocal and independently checked. Reachability means structural
reachability from a function entry, including both possible branch polarities;
it does not claim a constant condition is dynamically taken.

Value temporaries use the corresponding Core node ordinal, checked against the
program and function. An ordinary value defines one temporary. Short-circuit
values use two path-exclusive assignments into one non-SSA result slot: the
skipped path copies the left operand, the evaluated path copies the right.
Branch conditions and consumers read only the selected path's definition.
Literal payloads, operator tokens, nominal types, callee symbols/signatures,
parameter modes and authoritative place parent trees retain exact Core identity.
CFG `ARG` rows retain ordered argument/field temporary uses, labels and modes;
Core `EDGE` rows remain their independent authority.

Calls evaluate arguments left to right. A move with a call target reserves a
transfer until that call commits; an immediate move transfers at its evaluation.
Calls are the ownership commit boundary. Explicit loan-begin instructions follow
the loan's source evaluation, and loan-end instructions follow the call. The
stage makes no ordinary mutable-borrow noalias promise. Fatal arithmetic or
allocation terminates at its operation and has no automatic unwind edge.

Scope exits have explicit marker instructions, followed by ordered conditional
cleanup actions. Markers identify the verified Core exit and its source/region;
actions identify the exact cleanup leaf, owner, type and joined state. Actions
test the runtime armed state, release only an armed leaf, then disarm it. Moves
and owning call/return commits disarm exactly their transferred leaves. Nullness
is separate. Exits run inside out, reverse acquisition and reverse record-leaf
order. A return evaluates/transfers its result before its cleanup chain. Break
and continue use the matching loop's outer continuation or condition entry after
cleanup. Unreachable source regions remain inspectable and accurately labelled;
they cannot become unaccounted live effects.

The verifier is a separate forward structural refinement checker. It validates
Core first, then block/edge reciprocity, complete typed instruction payloads,
ordered operand uses and region continuations. It reconstructs every conditional,
loop, call loan and scope/leaf exit obligation from retained verified Core. Each
physical block/instruction must be claimed exactly once by that contract; no
builder status, region anchor, printer equality or cached admitted bit certifies
safety. This inductive ordering proof carries Core's definite initialization and
ownership proof across explicit paths. Independent test worklists additionally
check must-defined temporaries at every reachable use, including cyclic joins.

The separate Astra consumer walks the graph tables, calculating reachable blocks,
edges, joins, DFS backedges and reachable cleanup/loan/effect instructions without
traversing syntax, Flow events or the Core tree. Its facts are inspection, not
machine execution. Independent C0 executions remain reference evidence only.

Limits bound each arena to 65,536 entries, structural recursion to 192,
verification work to 8,000,000 and projection bytes to 16 MiB. Exhaustion emits no
partial public CFG. `--cfg-output-limit N` lowers only the output budget for
exact-boundary tests; the normal cap remains 16 MiB. Status 1 is `INVALID_CFG`, 2 `CFG_RESOURCE_EXHAUSTED`, 3
`CFG_DEFERRED`, 4 `INVALID_VERIFIED_CORE`; original Core/admission queries retain
their prior contracts. Whole compiler source and unknown effect policies remain
deferred. There is no SSA, LLVM emission, new machine backend or Stage-1 claim.

SSA-11 can consume the function/block/edge identities, non-SSA result slots,
explicit place writes and conditional owner/loan transitions. It must establish
dominance, typed def-use, phi/block parameters and owner-token joins independently;
no address-exposed place is implicitly promotable here.
