# Astra scalar semantics: ASTRA-SCALAR-1

The floating scalar types are exact [f32](f32.md) (IEEE binary32) and
[f64](f64.md) (IEEE binary64). Their width is semantic and target-independent.
Decimal literals convert directly to their expected floating format, defaulting
to f32 without stronger context. Same-type arithmetic rounds once per operation;
explicit `as` widens f32 exactly or narrows f64 nearest/ties-even. There is no
implicit promotion, integer/float conversion, remainder or floating bit operation.

Astra defines `int` and `bool` as distinct semantic value types. `void` describes
an absent return value and cannot be used as a value. These rules apply on every
target, independently of Vala, C, host architecture, or LLVM behavior.

## Integer values and arithmetic

`int` is **signed with exactly 32 bits of value representation**, ranging from
**-2147483648 (INT_MIN) through 2147483647 (INT_MAX)**. It is never target-sized.

Ordinary addition, subtraction, multiplication, and unary negation wrap:
reduce the mathematical result modulo 2^32 and interpret the result as signed
two's complement. Unary plus is identity. There is no overflow UB, implicit
overflow trap, or build-mode-dependent behavior.

| Expression | Defined value |
| --- | --- |
| `2147483647 + 1` | -2147483648 |
| `-2147483648 - 1` | 2147483647 |
| `65536 * 65536` | 0 |
| `-(-2147483648)` | -2147483648 |
| `+42` | 42 |

These are runtime meanings. Upstream IR retains operations; LLVM's ordinary
C builder may fold constant operands without an optimization pass. Wrapping is the ordinary baseline; checked, saturating, and
possibly overflow-reporting arithmetic may be added as explicit facilities.

## Division, remainder, and comparisons

Division truncates toward zero. For a nonzero divisor, let `q` be the
mathematical quotient truncated toward zero. Remainder is `a - q*b`; a nonzero
remainder has the dividend's sign.

| `a` | `b` | `a / b` | `a % b` |
| --- | --- | --- | --- |
| 7 | 3 | 2 | 1 |
| -7 | 3 | -2 | -1 |
| 7 | -3 | -2 | 1 |
| -7 | -3 | 2 | -1 |
| INT_MIN | -1 | INT_MIN | 0 |

INT_MIN divided by -1 wraps to INT_MIN; its remainder is zero. Target
instruction traps or LLVM poison are not valid implementations of this edge.

Division and remainder by zero are **deterministic runtime trap conditions**.
They have no numeric result. `1 / 0` and `1 % 0` pass semantic checking because
there is no general constant evaluator or constant-expression diagnosis.
LLVM-1 implements explicit intrinsic-trap control flow. EXEC-1 runtime tests
reach both traps in generated machine code. A trap is semantically non-returning:
it has no normal result and execution cannot continue past it. A native trap
instruction or abort-like fallback may manifest differently across targets;
no exact Unix signal is promised and no uniform-signal Astra runtime is needed.

`<`, `<=`, `>`, and `>=` compare signed int values. `==` and `!=` compare exact
values. All comparisons produce bool. They never use an unsigned or
representation-dependent ordering.

CALL-1's left-to-right rules include potential traps: binary left before right,
arguments first-to-last, then the call. In `a / b + effect()`, division must
complete before `effect()` runs. The compiler preserves this order through CFG
and SSA, including traps nested inside call arguments or bool conditions.

## Bool

`bool` has exactly two semantic values: `false` and `true`. Its compiler payload
remains `BooleanLiteral.FALSE/TRUE`, never an AstraIntValue containing 0 or 1.
Bool is not an integer subtype. Integer truthiness and implicit conversions in
either direction are errors. Bool conditions, equality, and unary `!` retain
their existing rules. NABI-1 separately maps bool transport to the logical
physical B1 channel, with canonical false/true values. Bool memory width,
and machine register encoding remain undecided. LLVM-1 realizes B1 values/call
channels as i1; this implies no one-bit storage, field packing, or addressable layout.

## Decimal literals and signed minimum

Syntax accepts `[0-9]+`. Leading zeroes remain decimal: `42`, `042`, and `00042`
all denote the same int value, 42. There are no hex/binary/octal forms,
separators, suffixes, or explicit-width literals.

An ordinary positive decimal literal must fit 0 through 2147483647. A direct
unary sign applied to an integer-literal form establishes signed literal
representability before checking its operand as an ordinary value. Parentheses
do not change that rule.

| Source | Semantic result |
| --- | --- |
| `0`, `00`, `-0` | 0 |
| `2147483647`, `0000002147483647`, `+2147483647` | INT_MAX |
| `-2147483648`, `-(2147483648)`, `-((2147483648))` | INT_MIN |
| `2147483648`, `+2147483648` | Out-of-range diagnostic |
| `-2147483649`, `-((2147483649))` | Out-of-range diagnostic |
| 1,003-digit historical huge magnitude | Out-of-range diagnostic |

The magnitude 2147483648 is never a valid positive int constant. Semantic
analysis forms INT_MIN directly from the negative literal syntax and produces
`(integer -2147483648 : int)`. Source `+123` similarly forms the value 123.
`-(-2147483648)` retains its outer negation, and `-(2147483648 + 0)` fails because
its positive operand literal is out of range. This is literal formation, not
general constant folding.

Diagnostics use source provenance and the deterministic message
`integer literal is out of range for 'int'`. Signed formation covers the sign
and its complete operand, including parentheses. The range algorithm checks
before each digit accumulation, so huge input cannot overflow host parsing.
The number of digits alone is not a limit: 1,003 zeroes represent zero.

## Authority and stage boundaries

Syntax and SourceFile/SourceSpan preserve exact source spelling. An immutable
`AstraIntValue` supplies the numeric authority of every checked int constant.
Its private storage uses host int64 safely; that implementation choice does not
make Astra int a host type or a 64-bit language type.

For `return 00042;`, the syntax dump shows `(integer "00042")`; semantic, Core,
CFG, and SSA dumps show `(integer 42 : int)`. The retained span still recovers
`00042` for diagnostics/debug tooling. No IR duplicates a spelling string or
re-parses text for numeric meaning. Stages own independent nodes and can share
the immutable numeric value, semantic type, and source provenance.

`--parse` and `--dump-syntax` accept oversized decimal magnitudes and preserve
every digit. `--check`, `--dump-semantics`, `--dump-core`, `--dump-cfg`, and
`--dump-ssa`/`--dump-nabi`/`--dump-llvm` reject out-of-range literals at semantic analysis, with no partial
stdout. This deliberately changes the historical huge-literal semantic-success
regressions while retaining their syntax coverage. The stored SEM-1 fixture
has 60 digits; Core/CFG/Place/Call fixtures have 1,003. All remain in the suite.

Calls and local initializers use the same range rule:
`identity(2147483647)` and `identity(-2147483648)` are valid;
`identity(2147483648)` fails before any downstream call is built.
`int x = 2147483648;` and `int y = -2147483649;` likewise fail.

The arithmetic utility exposes reference operations and an explicit
`IntArithmeticOutcome.VALUE` or `ZERO_DIVISOR_TRAP` outcome for division and
remainder. Trap returns carry no value. It is tested independently and is
available as an oracle for future implementations, not used for expression
folding in this milestone.

## Native signatures and LLVM body lowering

Semantic width fixes int's value domain and operation results. NABI-1's separate
[native scalar v0 contract](../abi/native-scalar-v0.md) physicalizes semantic int
as I32, bool as B1, and void result as an absent channel. Signatures have one
direct source-order channel per scalar parameter, at most one direct result,
and no hidden channels. They are a sidecar to SSA with native-internal linkage,
an unstable compiler-owned ABI identity, and no stable linker names or C ABI.

Parameter/return registers, stack layout, machine convention, and bool memory
layout remain open. LLVM-1 maps I32/B1/absent result to i32/i1/void in internal
fastcc functions. Wrapping +, -, *, and unary - carry no nsw/nuw; unary + is
identity. Comparisons use signed predicates, equality uses eq/ne, and bool
negation uses i1 xor with true.

Division/remainder branch to llvm.trap plus unreachable on zero, then guard
INT_MIN/-1 before raw sdiv/srem. Special paths supply INT_MIN for division and
zero for remainder. Calls and traps retain stored SSA order; no optimization
pass is required or run. No semantic/Core/CFG/SSA/NABI node acquires an LLVM
handle. `--dump-llvm` prints verified IR and `--check` includes its verifier.
Plain `astrac FILE` produces a host executable, optionally with `-o OUTPUT`,
requiring exact `int main()`. A private launch wrapper returns Astra main's int
result; on the qualified POSIX host, return 42 appears as process status 42.
This does not promise that all future operating systems expose all 32 result
bits. Machine tests include parameterized wrapping, signed comparisons,
division/remainder and INT_MIN edges, bool transport/joins, and a bounded matrix
using AstraIntValue as the oracle. No C signed-overflow arithmetic or raw LLVM
division-edge behavior defines expected results. See
[LLVM scalar v0](../backend/llvm-scalar-v0.md) and
[native execution v0](../backend/native-execution-v0.md).

See [ADR 0013](../decisions/0013-scalar-semantics.md) for rationale, safe host
implementation, and the narrow trap-ordering correction to CFG construction.
