# Break and continue

ASTRA-LOOPCTRL-1 adds two reserved keywords and statement forms:

```ebnf
break-statement    := "break" ";"
continue-statement := "continue" ";"
```

The semicolon is mandatory. Both statements are legal only inside a while body,
including its nested if/else arms. `break;` leaves the innermost enclosing while
and resumes with the statement after that loop. `continue;` reevaluates that
loop's condition, beginning the next attempted iteration.

```astra
int sum_odds(int n) {
	int i = 0;
	int sum = 0;
	while (i < n) {
		i = i + 1;
		if (i % 2 == 0) {
			continue;
		}
		if (i > 9) {
			break;
		}
		sum = sum + i;
	}
	return sum;
}
```

Nested loop transfers affect only the inner loop. The outer loop resumes after
an inner break; an inner continue reevaluates the inner condition. Neither exits
a function. A return still exits the entire function immediately.

Outside a loop, both statements parse successfully and fail semantic analysis:
`'break' is only valid inside a loop` or `'continue' is only valid inside a loop`.
The diagnostic highlights the keyword. Source after a transfer is still parsed
and checked, and remains visible as unreachable structure in CFG dumps. It
cannot execute, including any call or store there. Calls and arithmetic before
a transfer execute in their established order; a trap prevents the transfer.

Locals keep their existing lexical visibility. Break does not expose a body
local after the loop, and continue does not initialize a declaration it skips.
A false initial condition still executes zero iterations and preserves pre-loop
values. Even literal-true loops retain a structural false edge for completion
checking. `int f(bool c) { while (c) { break; } }` therefore fails flow checking.

## Compiler identity and inspection

Each checked while owns one exact loop-target object. A temporary semantic stack
selects the innermost target once. Zero-based function-local ordinals follow
source preorder, including unreachable source: outer `#0`, nested `#1`, next
nested sibling `#2`. A new function restarts at `#0`; identical ordinals across
functions never imply identical targets.

Semantic and Core dumps expose `(while #0 ...)`, `(break #0)`, and
`(continue #0)`. Core owns independent target objects translated by exact checked
identity. CFG maps those objects to header/exit blocks and uses only ordinary
branches. Multiple continue paths become ordinary header predecessors; break
paths become ordinary exit predecessors. Generic dominance frontiers discover
any necessary SSA header/exit parameters and edge arguments. LLVM phis use the
actual physical predecessors, even when arithmetic splits a transfer path.

All existing CLI stages and native executable compilation support these forms.
No new flags, runtime library, or NABI signature behavior is introduced.

## Boundaries

There are no labels, outer/multi-level transfers, break/continue values, or
expression forms. `break 1;`, `continue label;`, `x = break;`, and
`return continue;` are syntax errors. Other loop forms, `&&`/`||`, loop
optimization, liveness/pruned SSA, and ownership are outside this milestone.
See [while loops](loops.md) and [ADR 0018](../decisions/0018-loop-control-targets.md).

## Expression control flow in conditions

For `while (a && b)`, continue still targets the original while header, which
enters the full condition again. It never targets the previous expression join,
RHS block, or temporary initialization block. Break still targets the resolved
loop exit. Expression result joins and exit/local merges are independent;
[the loop fixture](../../tests/shortcircuit/fixtures/loop-short.astra) qualifies
both transfers through native execution.
