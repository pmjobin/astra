# Bitwise and shift values through the IR stages

[ADR 0042](../decisions/0042-bitwise-and-shift-semantics.md) and the
[language contract](../language/bitwise.md) define semantics independently of LLVM.

## Checked and Core authority

PrefixOperator.BIT_NOT and BinaryOperator.BIT_AND/BIT_OR/BIT_XOR extend the
existing CheckedPrefixExpression/CheckedBinaryExpression and CorePrefixValue/
CoreBinaryValue representations. The shared `accepts` authority enforces exact
same integer or bool operand/result types and whole-vector shape identity.
Boolean eager operations are distinguishable by their exact bool/mask type;
their bit-symbol spelling implies no integer conversion. ShortCircuitOperator
remains separate, and unary `!` remains bool/mask complement.

CheckedIntegerShiftExpression and CoreIntegerShiftValue retain IntegerShiftKind
LEFT/RIGHT, value operand, independently typed scalar count, exact result type
and provenance. Width derives from the exact value element IntegerType, checked
against result identity. There is no independent width field that can disagree.
IntegerShiftKind owns the invalid-count trap contract for every instance; right
mode derives from value signedness. Core verification rejects noninteger values,
vector/noninteger counts, wrong result identities, unsupported shapes and unknown
directions. Invalid dynamic values are legal operands that must trap at execution.

Direct checked constants outside `0,W)` reject in semantic analysis. Existing
typed integer constant nodes survive each lowering stage and preserve available
constant knowledge without syntax inspection downstream. No general folding or
separate forgeable "known valid" proof field is needed.

The dumps retain forms such as `binary & : u16`, `prefix ~ : i8`,
`binary & : bool<8>`, and:

```text
(shift-right-arithmetic : i16<8> (valid-range 0 15) (invalid-count trap)
	(value ...)
	(count ... : u32))
```

## CFG and SSA

Bitwise operations use the existing pure prefix/binary values after operand
evaluation. Eager bool evaluates left then right through normal value traversal;
it does not construct short-circuit branches. Existing &&/|| expression-level
CFG remains unchanged.

CfgIntegerShiftInstruction evaluates a CfgIntegerShiftValue in one ordered,
potentially trapping operation. The builder captures the value before the count,
including values preceding nested owned-transfer commits. This classification
also forces earlier enclosing operands to finish before a shift. The operation
validates after both expressions have executed; trapping never unwinds cleanup.
No target guards or lane loops appear in CFG. Ownership traversal visits both
operands and a pending owned call cannot defer their evaluation past commit.

SsaPrefixInstruction/SsaBinaryInstruction retain exact integer/vector/bool types.
SsaIntegerShiftInstruction has one value operand, one scalar count operand, one
exact result, direction and provenance. A vector input remains one whole vector
result. SSA verification checks value/count/result identities and legal direction.
Branch joins and loop backedges use ordinary whole-value block parameters.
No LanePlace, storage projection, vector memory or source count vector exists.

Checked nodes, Core, CFG and SSA can each be destroyed after constructing the next
stage. The retained types/operators/constants suffice without backlinks. Semantic,
Core, CFG, SSA and NABI code remain LLVM-free. ABI model/profile files do not change.

## LLVM realization

Integer and eager bool/mask operations emit exact and/or/xor at scalar or vector
width. Integer `~` and boolean `!` use xor with all-ones of the exact physical type.

Dynamic shifts compare the count in its original width: signed counts use slt
zero and sge W, combined with or; unsigned counts use uge W. The invalid edge
executes llvm.trap then unreachable. Only the valid continuation normalizes the
count, with truncation for a wider count or zero extension for a narrower count.
The proven range makes either conversion lossless. This is physical lowering,
not an Astra `as` or numeric coercion.

Vector counts use a defined zero vector seed, one inserted scalar count and zero
shuffle selectors. This backend-private splat creates no semantic VectorType.
The backend then emits one shl/ashr/lshr on the whole vector. Left shift has no
nsw/nuw, right shift has no exact. Direct known-valid constant counts omit guards.
An always-invalid count discovered by LLVM folding takes the trap edge and does
not cause an invalid constant shift to be constructed even in unreachable code.

LlvmBlockState.end is updated to the valid continuation. All phis use actual
final physical predecessors after count guards, including branch joins, loop
backedges and short-circuit joins; this reuses div/rem predecessor authority.
No helper runtime is added. Machine instruction choice, SIMD matching and byte
vector legalization are evidence only. Backend scalarization is allowed and
never changes Astra SSA's one-vector-operation contract.

Future rotates, per-lane counts, masked counts, compound assignment, bitcasts,
fixed point and vector memory require explicit additional semantic designs.
See the [qualification report for oracle, poison,
predecessor, machine, lifetime and memory evidence.
