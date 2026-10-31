# Short-circuit boolean expressions

ASTRA-SHORTCIRCUIT-1 adds `&&` and `||`. Both operands must be bool; the result is
bool. Int operands are errors, including `1 && true`, `true && 1`, and `1 || 2`.
The lexer maximally matches the two-character tokens. Single `&` and `|` remain
unexpected characters; `!` and `!=` keep their existing meaning.

From tightest to loosest, precedence is prefix `+ - !`, multiplicative `* / %`,
additive `+ -`, relational `< <= > >=`, equality `== !=`, logical AND `&&`,
logical OR `||`. Both logical forms associate left: `a && b && c` retains
`(a && b) && c`, and the same rule applies to OR. Thus `a || b && c` means
`a || (b && c)`; `a == b && c != d || e` means
`((a == b) && (c != d)) || e`. The compiler does not reassociate these trees.

| Form | Left evaluates to | Result and RHS evaluation |
| --- | --- | --- |
| `A && B` | false | false; B does not execute |
| `A && B` | true | evaluate B; result is B |
| `A || B` | true | true; B does not execute |
| `A || B` | false | evaluate B; result is B |

A always evaluates first, even in `trap_expr && false` or `trap_expr || true`.
Only B may be skipped. These are observable semantics for calls and runtime
traps. `false && ((1 / 0) == 0)` returns false and `true || ((1 / 0) == 0)`
returns true without trapping. Reversing either left value requires the RHS
and traps. A required trap has abnormal termination; no exact signal is specified.

Both operands are statically checked regardless of the left value. Consequently
`false && missing()`, `true || missing()`, and
`false && (2147483648 == 0)` are semantic errors. Zero division is a runtime
trap, not an integer-literal range or constant-expression error. There is no
constant folding in this milestone: even literal left operands retain the
structured operation and both CFG edges.

Logical expressions work in initializers, assignments, returns, if/while
conditions, prefix/equality expressions, and call arguments:

```astra
bool choose(bool a, bool b, bool c) {
	bool x = a && b;
	x = x || c;
	if (a && c) {
		x = b || c;
	}
	return x;
}
```

`consume(a && b, c || d)` finishes the first argument, including its conditional
RHS and result join, before beginning the second. The call executes after both
arguments. Assignment writes its local only after the complete RHS result exists.

A while header starts the full condition on every attempted iteration. Continue
returns to that original header, so both the left decision and any required RHS
are reevaluated. Break still exits the resolved loop. For
`while (i < n && i < 5) { i = i + 1; }` starting at zero, n = 0, 3, 10 produces
0, 3, 5 respectively. Short-circuit temporary state is not loop-carried state.

See [expression control flow](../ir/expression-control-flow.md) for the preserved
Core node, CFG temporary, SSA block argument, and LLVM phi. No bitwise operators,
logical compound assignments, ternary, assignment expressions, or implicit
conversions accompany this feature.
