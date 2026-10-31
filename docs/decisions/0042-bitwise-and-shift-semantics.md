# ADR 0042: exact bitwise and shift semantics

Status: accepted for ASTRA-BIT-1. Baseline: ASTRA-VEC-DOT-1,
`10159b5b4d57cbc8f3bb555a0cdc4cfe2f7477d1`.

## Decision

1. Integer bit operations are exact fixed-width Astra semantics.
2. Integer `&`, `|`, `^`, and `~` act on exact type-width bit patterns.
3. Their result retains the operand's exact IntegerType, width and signedness.
4. Binary integer bit operations require exact same IntegerTypes; ICONV is explicit.
5. Vector bit operations require exact same VectorTypes and apply scalar rules per lane.
6. Boolean `&`, `|`, `^` are eager boolean operations, without integer conversion.
7. Eager boolean operations support scalar bool and exact same bool<N> masks.
8. `&&` and `||` remain scalar short-circuit control-flow operators.
9. `!` remains the canonical boolean/mask complement.
10. `~` is integer-only, including integer vectors; bool, masks, f32 and pointers reject.
11. Shift result is the left operand's exact integer scalar/vector type.
12. The count is a separate ordinal operand of any scalar IntegerType.
13. Count interpretation is its exact mathematical integer value, independently of the value type.
14. Valid counts satisfy `0 <= count < element_bit_width`.
15. Invalid dynamic counts explicitly trap without returning or unwinding; no host signal is prescribed.
16. Invalid immediate checked integer constants reject statically, including direct negative literals. No general constant-expression evaluator is added.
17. Left shift retains the low W bits of the source pattern shifted left.
18. Signed left shift has no overflow UB and never traps for overflow.
19. Signed right shift is arithmetic, with explicit sign extension.
20. Unsigned right shift is logical, with zero fill.
21. Arithmetic right shift equals mathematical floor division by `2^count`, unlike truncating integer division on negative odd values.
22. No shift silently masks its count, including at the machine boundary.
23. Invalid counts never reach an LLVM shift; LLVM poison/UB is not Astra semantics.
24. Vector shifts apply one scalar count to every lane, validated once against element width.
25. Per-lane vector counts are unsupported.
26. Vector bit/shift operations remain one semantic value operation and one SSA operation/result.
27. No LanePlace is introduced.
28. No vector memory is introduced.
29. NABI requires no new type/channel/profile; all five existing profiles remain unchanged.
30. CABI and VAPI remain unchanged, including exact-width C integer and C vector exclusions.
31. LLVM and/or/xor/shl/ashr/lshr are backend realizations only. Shift normalization and scalar-count splatting are backend-private.
32. Future rotates, explicitly masked/wrapping counts, per-lane shifts and bitcasts require distinct semantic additions.

## Evaluation and representation

Evaluate the value/left operand, then count/right operand, exactly once. Eager
boolean and vector operations evaluate both producers even when the left operand
alone would determine the result. Validate a shift after both expressions finish.
A potentially trapping shift is an ordered CFG operation and cannot move freely
across effects or pending owned-transfer commits.

PrefixOperator.BIT_NOT and BinaryOperator.BIT_AND/BIT_OR/BIT_XOR extend the
existing verifier-visible exact operator authority. Dedicated checked/Core/CFG/SSA
integer-shift nodes avoid the equal-operand-type contract of binary arithmetic.
They retain direction, result/operand identity, independently typed scalar count,
provenance and the hardwired invalid-count trap contract. Element width derives
from the retained exact type. Existing typed constant nodes retain immediate-count
knowledge across stage destruction; no downstream source-syntax dependency or
independently forgeable width/proof flag is introduced.

The backend guards in the count's original physical width and signedness, then
normalizes a proven valid count to the value's element width. It uses a defined
zero vector seed and zero selectors to splat a scalar count for vector shifts.
This creates no Astra count VectorType or ICONV. Ordinary shift builders attach
neither nsw/nuw nor exact. The existing LlvmBlockState.end authority records guard
continuations for branch/loop/short-circuit phi predecessors. If LLVM folds a guard
to always invalid, its unreachable continuation receives a harmless zero value;
the compiler never asks LLVM to fold an invalid shift into poison.

## Precedence and future type closers

From strongest to weakest (ordinary binary forms associate left):

| Level | Operators |
| --- | --- |
| Unary | `+` `-` `!` `~` address-of `&` |
| Existing integer conversion | `as` |
| Multiplicative | `*` `/` `%` |
| Additive | `+` `-` |
| Shift | `<<` `>>` |
| Relational | `<` `<=` `>` `>=` |
| Equality | `==` `!=` |
| Bitwise AND / eager bool AND | `&` |
| Bitwise XOR / eager bool XOR | `^` |
| Bitwise OR / eager bool OR | `\|` |
| Logical AND | `&&` |
| Logical OR | `\|\|` |

Primary calls/field access and postfix lane extraction keep their existing
positions. Address-of keeps its existing restricted identifier/Place grammar.
The established `as` level between unary and multiplication is unchanged.
`a > b & c > d` therefore means `(a > b) & (c > d)`.

The lexer maximally matches `&&`, `||`, `<<`, and `>>`. A token owns a source span
and has no hidden irreversible lexer state. Future `Outer<Inner<int>>` will need
contextual type-close splitting of a `>>` token into two one-byte spans, which
can be implemented by the parser's token lookahead without replacing the lexer.
Current vector type syntax does not nest; no splitting mechanism or generics are
needed or added in BIT-1.

## Boundaries

No rotates, `>>>`, count masking, compound assignment, bool/integer casts,
f32/integer bitcasts, pointer conversions/tagging, hexadecimal literal expansion,
fixed point, vector memory/fields/gather/scatter, or C ABI expansion. Compound
assignment needs a separate evaluation-once Place design; normal bit/shift value
operators make no promise about future storage projections. Existing exact
integer, ICONV, F32, lane, DSP, dot/MAC and ownership semantics remain authoritative.

See [language rules](../language/bitwise.md), [IR rules](../ir/bitwise-shifts.md),
and qualification.
