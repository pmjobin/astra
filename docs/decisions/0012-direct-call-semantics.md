# ADR 0012: Direct call semantics

Status: accepted for ASTRA-CALL-1.

## Decision

1. Direct calls resolve once during semantic analysis to the exact compilation-unit
   FunctionSymbol. Only an identifier can be a callee.
2. Downstream builders translate object identity through temporary
   `FunctionSymbol → CoreFunction → CfgFunction → SsaFunction` maps. Names and
   ordinals are debug information, never downstream binding authority.
3. Each stage establishes all function identities before translating bodies.
   Functions may be called before or after their source declaration.
4. Self recursion and mutual recursion are valid. No termination/execution,
   call-graph, SCC, or interprocedural analysis is introduced.
5. Every direct call is conservatively effectful. Unused, repeated, and
   source-discarded calls remain distinct operations. No CSE, DCE, inlining,
   purity inference, or call motion is introduced.
6. Current expression operands evaluate left-to-right: binary left, binary
   right, then operator. Prefixes evaluate their operand before the operator.
7. Call arguments evaluate first-to-last, then the call executes. Initializers
   precede initialization; assignment RHS precedes Store; returned expressions
   precede Return; conditions precede branching. This is observable language
   semantics. Future optimization may reorder only after proving equivalence,
   including potentially observable operations.
8. Semantic signatures do not prescribe physical/native ABI signatures.
   There is no calling convention, linkage, mangling, register/stack assignment,
   hidden parameter, sret, physical int/bool encoding, or LLVM signature here.
9. Calls do not introduce first-class function values, callable locals, indirect
   calls, function pointers, delegates, or closures.
10. CALL-1 has one direct-function namespace. Duplicate names remain errors;
    overload resolution does not exist. A local or parameter may share a function
    spelling: `name(...)` uses function authority, bare `name` uses lexical value
    authority. This does not freeze the final callable-namespace policy.
11. Call edges must never create reference-count ownership cycles between
    functions and their bodies, including self and mutual recursion.
12. Programs strongly own function entities, which own bodies. Calls store
    non-owning exact callee references using GLib `WeakRef`. CheckedProgram owns
    FunctionSymbols through CheckedFunctions. Reading a weak target temporarily
    retains a live callee, or returns null after expiration. The checked-to-Core
    boundary and downstream verifiers reject expired or foreign program targets.
13. A call statement may target void or non-void. A non-void result is explicitly
    discarded without an unused-result warning; CFG and SSA retain its definition
    even when it has no consumer. Future warning policy remains open.
14. A value call must return non-void. A void call in a value-required context
    receives a deterministic semantic diagnostic.

Arguments require exact positional count and exact semantic type identity, with
no conversions, names, defaults, variadics, or spreads. Current value types are
int and bool; void is only a return shape. Ownership channels and ABI signatures
are deferred.

## Representation and alternatives

Core retains nested CoreCallValue and CoreCallStatement nodes. Leaving effectful
calls nested in CFG values would hide execution order. Instead, operand-first
lowering appends CfgCallInstruction after its arguments and substitutes its
CfgCallResultValue for a non-void use. Results are Values, never Places. They
have no instruction backlink; temporary verifier tables establish one defining
call and enforce same-block definition-before-use.

SSA translates CFG calls in instruction order, mapping each exact result to an
SsaInstructionResult. SsaInstruction.result is optional for void calls; existing
computations still require a result. A separate value-producing instruction
hierarchy would add unnecessary structure for this concrete distinction.

Calls are instructions, never intraprocedural successor edges. Reachability
does not visit callees. Disconnected calls remain in CFG and are excluded only
by SSA's established reachable projection. Calls cannot currently alias caller
locals because there is no address-of, ref/out, pointer, or capture channel;
scalar Place promotion remains valid without implying purity.

Plain Vala `weak` fields generate raw C pointers on the qualified host and do
not clear on finalization. Expiration regressions demonstrated that they cannot
safely resolve dead callees; GLib `WeakRef` supplies that contract without
registries, strings, leaks, or manual refcount-breaking cleanup.

## Validation

Parser/semantic tests cover grammar, collisions, exact arguments, diagnostics,
recursion, and result restrictions. Standalone Core/CFG/SSA tests construct and
reclaim recursive graphs without upstream models and reject malformed calls.
Pipeline tests destroy syntax/checked, Core, and CFG before inspecting the next
stage, for forward, self-recursive, and mutually recursive calls. Goldens prove
order, discarded results, bool conditions, Place promotion, joins, huge literal
arguments, and unreachable projection. Strict C and LLVM firewalls remain.

See [calls](../language/calls.md) and [cross-stage IR](../ir/direct-calls.md).
