# Statements and control flow

R-CONTROL. Blocks introduce lexical regions. `if` requires bool and selects one
branch. `while` tests before each iteration; zero iterations are valid. Locals
initialized inside its body belong to that cleanup region. `return` computes
its result before exiting cleanup scopes. Supported loop `break`/`continue`
must retire exited regions rather than abandon ownership obligations.

Use braces for declarations, nested controls, throwing statements and compound
assignments in control bodies. Formatter elisions are selected by the actual
parser. Visual brevity is not proof that a body satisfies the parser's “one
simple statement” rule. The default authored style preserves unproven braces.

R-FOR-BOUNDARY. `for` has parser representation and historical continue-step
contracts. Current native Flow refuses this whole program, so this edition
does not promise its native execution:

```astra example=negative-for
language astra27b;
int main() {
	int total = 0;
	for (int i = 0; i < 6; i += 1) {
		total += i;
	}
	return total;
}
```

The [Guide](../guide/values.md) uses an admitted `while` loop with explicit
progress. Every repeating path must perform the appropriate update. A manual
translation must preserve where a step occurs relative to `continue`; replacing
the keyword alone does not establish equivalence.

R-FOREACH. Current native `foreach` admits checked integer range/lazy sequences
with immutable element bindings. Do not infer general array, container,
stateful-iterator or asynchronous iteration from historical manuals. The
collections fixture uses `foreach` for a range and indexed `while` for an owned
array. Concrete iteration authority must exist before lowering.

R-MATCH. Expression matches use enum-qualified cases with parentheses, including
zero-payload variants. Every expression arm ends in a semicolon. Checked
variant/payload identity controls extraction rather than spelling alone. Cases
must cover the domain without overlap, including nested pattern products.
Payload bindings are scoped to their arm. Inspecting and consuming matches have
different ownership effects; see [Ownership](ownership.md).

`with`, general comparison chains and historical iterator protocols have no
general native credit in this edition. Their future admission cannot be inferred
from source representation. Throwing control and its cleanup obligations are
described separately in [Errors](errors.md).
