# Checked types and the first expression slice

The checked component consumes `BindingIndex`, retaining the existing single
program/source owner chain. It does not call C0 or recover types from source
substrings. `types.astra` owns geometrically grown descriptor/argument tables;
`elaborate.astra` translates typed type syntax and declaration signatures;
`expressions.astra` and `statements.astra` execute the bounded checking slice.
The development consumer is `tests/selfhost-typecore/query.astra`.

`TypeId` and `SignatureId` are distinct nonowning table ordinals. An ID is used
with its originating owner. Public table reads take that owner and compare a
retained shared native identity token before checking the ordinal. This reuses
[the established identity pattern](../../docs/language/shared-identity.md).
No transient Vala address, type spelling, LLVM layout or global counter supplies
identity. Equal contents in separate sources never merge nominal declarations.
Nominal recursion stops at a declaration head; argument recursion has depth 128.

A structural descriptor holds its constructor, exact nominal definition if any,
extent/lane count and ordered typed argument edges. Callable result precedes its
parameters. Edge flags preserve nonnull, borrowed and owned channels. Declaration
signatures additionally retain their exact Binder symbol, throws type, async,
foreign/signalling and dispatch metadata. The original AST retains all additional
policy data; no ABI or ownership-flow proof is implied by a signature row.

`complete` seals graph construction; consumers must still inspect each use's
`deferred` code. Logical TypeId equality and qualifier compatibility are
separate: missing nonnull flow proof is reason 18, and pending ownership/borrow
proof is reason 19. Explicit null violations are diagnosed after ordinary
type checks. A declared qualifier is retained even when its proof is deferred.

The type graph and checked uses are separate from syntax. Expression uses retain
the original node and byte span. Unsupported families have a nonzero, named
reason and no invented type. Dependent contexts remain explicit. The finite
scalar checker has exact operand types and contextual literals; it introduces
no implicit promotion or evaluation/overflow policy. Ordinary integer operations
retain C0's wrapping semantics; shift/conversion traps and floating evaluation
are later execution/lowering responsibilities.

`BindingIndex.complete_reference` accepts only an original deferred field edge
with its exact owner, or a reason-7 lexical callable candidate. It retains the
reference identity and updates the existing reverse list. This closes individual
reason-1/3/7 instances, without claiming those entire categories are resolved.
The original seven-reason ledger remains valid for all other instances.

The internal `astra-types/1` observation extends `astra-bindings/1` with:

- `T id kind nominal extent depth name-hex [argument:flags ...]`.
- `Y symbol type flags signature` and `F signature symbol callable error flags dispatch`.
- `U node path-hex start end type flags deferred syntax-kind`.

`--types FILE...`, `--type-at PATH OFFSET FILE...` and `--signature PATH OFFSET
FILE...` inspect retained owners after parser/lexer handles are gone. This is a
development observation, not a public serialization or native ABI.

The source-guided family matrix and explicit follow-on work are recorded in
[typecore-port.json](typecore-port.json). Frozen fixtures precede implementation;
raw C0/native/timing/memory receipts stay in external runtime storage. Run:

```sh
python3 -B tests/selfhost-typecore/freeze.py --compiler /absolute/astrac \
  --runtime "$HOME/Workspace/codex/work/astra/runtime/typecore-frozen"
python3 -B tests/selfhost-typecore/run.py --compiler /absolute/astrac \
  --baseline "$HOME/Workspace/codex/work/astra/runtime/typecore-frozen" \
  --build "$HOME/Workspace/codex/work/astra/build/selfhost-typecore-5" \
  --runtime "$HOME/Workspace/codex/work/astra/runtime/typecore-runs"
```

The production compiler, complete checked model, ownership/borrow flow, generic
specialization, independent Core/CFG/SSA verification and LLVM backend remain
Vala. The next semantic milestone needs broader checked statements/expressions,
transitive generic storage/capability proofs and ownership/lifetime integration.
