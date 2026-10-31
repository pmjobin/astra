# Operators

`expression as Type` also performs [explicit scalar integer↔floating conversion](numeric-conversions.md).
The operand is evaluated once without destination context. Integer→floating
rounds nearest/ties-even; floating→integer truncates then checks the exact range
and traps on failure. Existing precedence, integer modulo and f32↔f64 rules are
unchanged. [Literal suffixes](floating-literals.md) select precision before rounding.

Concrete scalar arithmetic and comparisons follow [scalar semantics](scalars.md),
[integers](integers.md), [f32](f32.md) and [f64](f64.md). Boolean short-circuit
operators use [conditional control flow](short-circuit.md); eager bitwise and
integer shifts follow the [BIT contract](bitwise.md). Vector operations retain
their [element-family and mask rules](vectors.md).

## Explicit generic capabilities

On TypeParameterType, GEN-CAP-1 authorizes only declared families: Eq (`==`, `!=`),
Ordered (`<`, `<=`, `>`, `>=`), Numeric (binary `+`, `-`, `*`, `/`), Bitwise
(`&`, `|`, `^`, `~`) and Shift (`<<`, `>>` with concrete scalar integer counts).
No family implies another. Generic literals, unary minus, remainder and member
access remain unsupported. Comparisons produce bool. See [capabilities](generic-capabilities.md).
