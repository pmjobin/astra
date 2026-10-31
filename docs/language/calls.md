# Native direct calls and C boundaries

GEN-1 adds [explicit generic calls](generic-functions.md), such as
`identity<f64>(1.25)` and `identity<i16<8>>(value)`. Every call supplies the full
ordered type list; inference and defaults are absent. Calls bind exact definition
and type identities, substitute the checked signature, and become ordinary direct
calls through Core monomorphization before CFG. Calls from methods, constructors
and property accessors share the same compilation-wide canonical instance registry.

Astra supports direct calls to native definitions and explicit C imports
declared in the same compilation unit:

```astra
int first(int x) {
	return second(x);
}

int second(int x) {
	return x + 1;
}
```

All signatures are collected before body checking. Earlier calls, forward calls,
self recursion, and mutual recursion are valid. The compiler checks these
representations; it does not execute calls or analyze termination.

## Syntax and lookup

```text
argument-list   := expression ("," expression)*
call-expression := identifier "(" argument-list? ")"
call-statement  := call-expression ";"
```

Free calls use an identifier callee. [Struct methods](methods.md) additionally
use `local.method(...)` or `this.method(...)`, with an exact member target and
a separate implicit receiver. Calls bind more tightly than prefixes and
binary operators. Nested argument calls are allowed. Trailing commas and
arbitrary expression statements are unsupported. `1 + 2;`, `x;`, `true;`,
`(f)()` and `f()()` are invalid. Struct-pointer and arbitrary-expression method
receivers remain unsupported.

`name(...)` resolves through compilation-unit function authority; bare `name`
uses lexical parameters/locals. A permitted local or parameter spelling equal
to a function name does not hide that direct function. Callable locals do not
exist: if no function has that spelling, the call reports an unknown function.
Duplicate top-level names remain invalid, including different signatures.
There are no overloads or function values. This is the current direct-call
policy, not a final policy for every future callable construct.

## Arguments and results

Arguments are positional with exact semantic types. Unannotated declarations
require exact arity. A trailing [caller-information suffix](caller-information.md)
permits omission of only that suffix; supplied values remain ordinary arguments.
No implicit conversion, named argument, general default expression, variadic,
or spread rules apply. For
`int add(int a, int b)`, `add(1, 2)` is valid; `add(1)`, `add(1, 2, 3)`, and
`add(true, 2)` fail.

A call expression must have a supported non-void native result. Integer, bool,
f32, vector, raw pointer and nominal handle results use their existing contracts;
owned results require an ordinary ownership-consumption context. A void call cannot initialize a
local, supply an argument, be an operand/condition, or provide a return value.
A call statement can invoke either kind of function:

```astra
int value() {
	return 1;
}

void ping() {
	return;
}

void work() {
	ping();
	value();
	return;
}
```

`value();` discards its result without a warning. The call and result definition
survive through SSA. Void calls have no result value. The existing return-shape
rule still rejects any `return expression;` in a void function.

Diagnostics name the callee and expected/provided arity or type. Unknown
functions point at the identifier; arity and void-value errors cover the call;
argument-type errors cover the offending checked argument. Resolution, arity,
and the void-value restriction precede argument checking; argument errors are
selected in source order. Unknown functions have a distinct diagnostic from
unknown value names.

## Evaluation and effects

Current expression evaluation is left-to-right:

| Construct | Order |
| --- | --- |
| Eager binary | Left operand, right operand, operator |
| Short circuit | Left operand, decision, required RHS only, bool result |
| Prefix | Operand, operator |
| Free call | Arguments first-to-last, execute call |
| Method call | Receiver, arguments first-to-last, execute call |
| Local declaration | Initializer, initialize Place |
| Assignment | RHS, store into Place |
| Return | Returned expression, return |
| If | Condition, branch |

`outer(inner1(), inner2())` calls inner1, inner2, then outer.
`left() + right()` calls left, right, then adds. This is a language rule,
independent of the host C compiler's expression-order rules.

Every call is conservatively effectful. `f(); f();` remains two calls even if
the current body is trivial. No unused-call removal, CSE, reordering, or inlining
occurs. Future optimization needs proof of equivalent behavior before moving
calls or other potentially observable operations.

NABI-1 now plans a separate [native scalar v0 signature](../abi/native-scalar-v0.md)
for every function: int → I32, bool → B1, and void → no result channel. Scalar
parameters use one direct channel each in source order; scalar returns use one
direct result. Those free-function signatures have no hidden or adaptation channels. METHOD-1
adds a separate first PTR receiver channel to method signatures using the existing
pointer-capable profiles; explicit parameters/results keep their ordinary rules. Calls validate against
the exact mapped NativeFunction, including forward/self/mutual recursion.

This ABI is compiler-internal and unstable. Functions have native-internal
linkage intent, without stable linker names, C ABI, machine register/stack
assignment, bool memory layout, or LLVM types. The signature sidecar adds no
body operations. LLVM-1 preserves effectful calls and the observable order of
scalar traps. There are no function pointers, delegates, closures,
ownership channels, or runtime generics.

LLVM-1 realizes current native functions as LLVM internal fastcc definitions
with deterministic backend-local `astra.fn.N` names. Every Astra call uses the
same convention and exact mapped function identity. All functions exist before
bodies, so forward/self/mutual recursion works without name lookup. LLVM
signatures come from NABI I32/B1/absent result as i32/i1/void. These names and
fastcc are implementation choices, not stable native ABI or C interoperability.

Stored SSA order survives physical lowering: left/right calls precede addition,
nested arguments precede the outer call, choose-call arm results join through
phis, and a division's guards and successful continuation separate preceding
from following calls. Void and discarded-result calls remain present. LLVM
verification is mandatory, with no optimization pipeline. EXEC-1 executes
direct, forward, self/mutual recursive, and choose-call workloads after native
object emission and host linking. See [the backend](../backend/llvm-scalar-v0.md).

Executable entry must be `int main()` with zero parameters. This source
function keeps ordinary native-call semantics, internal linkage, and fastcc.
The backend synthesizes a private external process-entry wrapper that calls
its exact LLVM identity and returns its result. Source calls to `main()` still
target the internal function, including recursion. This launch boundary is
not C/VAPI interoperability, a stable exported symbol contract, or argc/argv
support. Entry policy applies only to executable compilation; ordinary checking
and dumps accept otherwise-valid functions named main with other signatures.
See [native execution v0](../backend/native-execution-v0.md).

See [ADR 0012](../decisions/0012-direct-call-semantics.md) and
[direct-call IR](../ir/direct-calls.md).

## Short-circuit arguments

[Logical expressions](short-circuit.md) preserve CALL-1's left-to-right argument
rule. `consume(a && b, c || d)` completes the first expression and its join before
starting the second, then calls consume. In `left() && right()`, left always
executes and right executes only if left returns true; OR instead requires right
only when left returns false. Static checking still visits both call operands.
Earlier argument calls and potential traps remain before later short-circuit
regions, even when an earlier result is consumed across several CFG blocks.

## C call domain

`extern(C) int c_add(int a, int b);` declares an exact C target in the same
unique function namespace. The equivalent `int c_add(int a, int b);` in a
[VAPI file](vapi.md) produces the same CFunctionSymbol before bodies are checked.
All VAPI files merge with source externs and native/exported definitions; duplicate
names reject even when signatures match. A checked call binds its native or C domain once;
forward imports work just like forward native signatures. C parameters and
results use int, with void results also allowed; bool foreign signatures reject.
Int results can be discarded without removing the call. Imported void cannot be
used as a value. An imported main is never executable entry.

C calls preserve Astra's left-to-right ordering, short-circuit suppression, and
loop/transfer behavior. They are conservatively effectful and not CFG successors.
Native calls keep NABI/internal/fastcc. C calls use separate CABI I32 channels,
external declarations, exact symbol names, and default C convention. Link objects
supply implementations; check/dump modes do not resolve symbols. See
[C interoperability](c-interop.md) and [ADR 0020](../decisions/0020-c-scalar-imports.md).

## Calls to exported functions

`export(C)` leaves the function's `DirectCallableSymbol` domain NATIVE and its
exact `FunctionSymbol` unchanged. Native callers, forward calls, self recursion,
and mutual calls all map to its native Core/CFG/SSA/NABI identities and internal
fastcc LLVM function. `CExportSymbol` never participates in callable lookup.
Only foreign callers use the external ccc wrapper, which calls that exact native
target fastcc. Export adds no conversions or expression/effect semantics.
See [C exports](c-exports.md).
