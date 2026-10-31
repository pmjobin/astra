# While loops

Astra supports pre-test, braced while loops:

```astra
int count(int n) {
	int i = 0;
	while (i < n) {
		i = i + 1;
	}
	return i;
}
```

The grammar is `"while" "(" expression ")" block`. Parentheses and braces are
mandatory; an empty body is allowed. The condition must have semantic type
`bool`: `while (1) {}` is invalid. There is no integer truthiness or implicit
conversion.

The condition executes before each attempted iteration. A false initial
condition executes the body zero times. After normal body completion, the
condition executes again using current local values. Calls, arithmetic, and
possible traps in the condition retain their left-to-right evaluation order
each time. A condition call is neither hoisted nor cached. A return in the
body exits the function immediately; no following body operation executes.
`break;` exits the innermost loop, and `continue;` reevaluates its condition.
Both transfers skip subsequent body operations. See [loop control](loop-control.md).

## Scope and local state

The body has one lexical child scope. Lookup searches current locals, enclosing
locals, then parameters. A local becomes visible only after its initializer is
checked, remains visible in later body statements and nested scopes, and cannot
escape the body. `int x = x + 1;` cannot refer to its own new declaration.
Declaring a name already visible as a local or parameter is rejected. This
retains BRANCH-1's conservative policy without deciding general shadowing.

An outer local such as `i` above is the same mutable storage in the condition,
body, and continuation. A body-local declaration also has one compiler identity,
but its initializer executes on every dynamic visit:

```astra
int next_count(int n) {
	int i = 0;
	while (i < n) {
		int next = i + 1;
		i = next;
	}
	return i;
}
```

`next` has no value before entering the body and is not visible after the loop.
Nested while/if bodies follow these same rules. Sibling scopes can independently
declare the same spelling with different identities.

## Conservative completion checking

Constant-condition analysis is not implemented. Both edges remain in the graph
for `while (true)` and `while (false)`. Consequently both of these functions
have valid checked/Core structure but fail `--check` because the false edge
reaches the end of a non-void function:

```astra
int partial(bool c) {
	while (c) {
		return 1;
	}
}
int constant_partial() {
	while (true) {
		return 1;
	}
}
```

A return after the loop completes those paths. Void functions may reach their
end normally. Source after a return remains available in CFG dumps as unreachable
structure, then disappears from SSA's reachable projection.

## Modes and boundaries

All existing parse/check/dump modes support loops. `--check` includes LLVM
verification and performs no execution. `astrac FILE -o OUTPUT` compiles loop
programs through the existing host-native path, requiring `int main()` as usual.
No flags or Astra runtime library are added.

Break and continue are reserved keywords. Labels, multi-level transfers,
transfer values and do/while remain unsupported. Later extensions add scoped
for loops, [foreach iteration](iteration.md), short-circuit conditions and
public O0/O1/O2 optimization. Those extensions retain the loop target and
cleanup rules described here.
See [ADR 0017](../decisions/0017-while-loop-control-flow.md) and
[cyclic control flow](../ir/cyclic-control-flow.md).

## Short-circuit conditions

`while (i < n && keep_going(i))` evaluates the comparison on every attempted
iteration and calls keep_going only when it succeeds. The original while header
enters a fresh expression-evaluation region; the final bool join chooses body or
exit. Its synthetic temporary never becomes incoming loop-carried state.
Continue re-enters that original header; break still selects the exact exit.
See [short-circuit semantics](short-circuit.md).
