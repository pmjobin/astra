# Expressions and evaluation

R-EVALUATION. Runtime operands are captured in written order. Named arguments
map values to formal positions after capture; formal order does not reorder
side effects. A receiver is prepared before explicit arguments. Consuming calls
reserve owners and commit transfer at the checked invocation boundary. If a
later operand throws, abort cleanup must retire fresh temporaries and preserve
the required owner state. Existing named-call regressions independently observe
traces and destructor counts for ordinary, nested and throwing operands.

Named arguments require unique declared parameter names and every required
argument. Positional arguments may precede labels, but cannot follow them.
A hidden receiver is not an extra labelable formal. Intrinsics and range
operations can require exact positional signatures rather than general labels.

```astra example=negative-label
language astra27b;
int identity(int value) {
	return value;
}
int main() {
	return identity(other: 42);
}
```

R-SHORT-CIRCUIT. `&&` and `||` evaluate their right operand only when needed.
`condition ? first : second` selects one checked result/ownership arm. Expression
matches evaluate one scrutinee and one selected arm. Boolean bitwise operations
are eager; they must not guard an operation that requires short-circuit safety.

R-PLACE. Compound assignment prepares a destination once, obtains its old value,
then evaluates and applies the RHS. Repeating an indexed destination in a manual
rewrite can change effects. Readonly fields and computed properties are not
arbitrary compound destinations. Bounds validation precedes actual memory access;
it grants no LLVM alias promise. Existing compound tests observe RHS mutation
and exact index effects, rather than merely comparing a final arithmetic value.

## Binding and boundaries

From weakest to strongest, binary powers are logical or, logical and, bitwise
or/xor/and, equality, ordering, shifts, modern ranges, addition, multiplication
and `as`. Prefix/postfix forms bind more tightly. [Grammar](grammar.md) gives the
table and special conditional/match forms. Binary operators normally associate
left; ordering chains have their own syntax family.

R-CHAIN-BOUNDARY. Native Flow currently refuses this representative chain:

```astra example=negative-chain
language astra27b;
int main() {
	int value = 2;
	if (0 < value < 4) return 42;
	return 1;
}
```

Use two comparisons joined by `&&` in admitted code. Existing parser support is
not execution proof. No generalized user-defined operators or implicit numeric
promotion are specified here. Name/type checking may succeed before an independent
owner, Core, CFG, SSA or physical verification boundary refuses the program.

## Observing written order

R-ORDER-TRACE. The [trace example](../guide/values.md#observing-evaluation-order)
passes arguments in the written order last, first, middle. Its independent C
observer records 312, while the callee receives formal values 1, 2, 3 and
computes 123. The same program observes that skipped logical and conditional
operands never call the observer. These two observations distinguish operand
capture order from parameter placement and branch selection.

R-CALL-ABORT. In a consuming call, evaluating an owner operand reserves the
actual binder slot. The callee becomes responsible only at commitment. The
Guide's [throwing-operand example](../guide/text-errors.md#cleanup-when-a-later-argument-fails)
places the right owner first, the left owner second, and a potentially throwing
marker last. Both successful entry and aborted entry retire each object once.
The returning paths check destructor counts and sums independently, rather than
using a successful final scalar alone as cleanup evidence.

Receiver preparation, target/index preparation, argument capture and call entry
are distinct boundaries. A compound indexed store validates its captured target
before evaluating its RHS. Copying a textual destination into two expressions
can change the number and order of effects. The retained source/Flow, Core,
CFG, SSA and physical consumers preserve these distinctions; none can be
replaced by the emitter's own trace or a trusted cached success bit.
