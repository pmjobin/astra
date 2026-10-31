# ADR 0072: Exact named compile-time constants

Status: accepted and implemented by ASTRA-CONST-1.

`const NAME = expression;` and `const Type NAME = expression;` introduce exact
named compile-time scalar values at native top level and in local statement
position. Lowercase `const` is reserved in native source. Other cases, independent
VAPI syntax and physical C symbol strings are unchanged. Runtime immutable
bindings remain undecided; `var` keeps its existing meaning.

The admitted types are bool, i8/u8/i16/u16/int (canonical i32)/u32, f32 and f64.
Explicit types use ordinary TypeSyntax and ordinary initializer context. Inferred
constants provide no destination context. A reference retains its resolved exact
type; its original literal spelling is never recontextualized. Ownership,
aggregate copyability and generic capabilities cannot grant constant eligibility.

The bounded expression subset consists of scalar numeric/bool literals, constant
references, parentheses, existing scalar unary/binary/short-circuit operators and
accepted explicit scalar `as` conversions. Every initializer is statically
checked, including unused declarations and runtime-unreachable local declarations.
Both short-circuit operands must satisfy names, types and subset eligibility;
only required operands undergo value evaluation. User/native/foreign/library
function execution, memory, allocation and ownership operations are excluded.

Top-level declarations join the whole native source program's value namespace.
They support cross-file forward references. Duplicate constants and callable
collisions reject; unrelated type/member namespaces remain separate. Locals
follow declaration-before-visibility and the existing prohibition on hiding visible
bindings. A local initializer cannot refer to its new binding. Constants have
exact symbols and no Place, storage ordinal, owner or emitted data symbol.

Top-level dependency collection includes both sides of short-circuit expressions.
An iterative visiting/completed traversal detects cycles with per-file locations,
evaluates each valid declaration once and retains its typed value. Invalid unused
declarations reject. Canonical source order and existing per-kind function/type
queues remain independent of command-line file order.

Integer operations reuse finite-width value authorities: wrap at every operation,
truncating signed division, dividend-signed remainder, MIN/-1 wrapping, MIN%-1 zero,
checked shift counts and explicit sign-fill right shift. Integer conversions retain
modulo destination-width semantics. Required traps become constant-context errors.

Floating arithmetic uses shared binary32/binary64 format descriptions and exact
compiler-only integer/rational evaluation, with nearest/ties-even rounding after
each operation. Signed zero, subnormals, nonfinites, strict operation order and
non-contraction are preserved. Newly produced compile-time arithmetic NaNs use a
positive quiet NaN with only the quiet payload bit set. This deterministic compiler
choice imposes no payload/sign requirement on runtime NaN arithmetic. Transport,
unary sign changes and existing cross-format conversion rules remain unchanged.
Integer-to-float conversion rounds nearest/even; float-to-integer truncates then
range-checks, diagnosing nonfinite/out-of-range values only when evaluated in a
required constant context. Ordinary runtime conversion traps remain runtime traps.

Fixed-array `T[expression]` dimensions use this same semantic authority. The result
must be an admitted integer with mathematical value 1..1024. Resolving a dimension
is not an expression cast. Empty `[]` remains a slice; vector lanes and runtime
`new T[count]` retain their existing rules. Exact ArrayType dimensions and scalar
values are final before executable Core.

Alternatives considered: runtime immutable locals would require initialization,
storage and ownership decisions that do not serve this feature; Core/LLVM folding
would violate the semantic boundary and make legality depend on optimization;
reusing host floats would make rounding and host state authoritative. The selected
implementation reuses ordinary checking and scalar value nodes, adds a bounded
compiler evaluator, and erases declarations in the existing Core builder. No new
runtime, ABI, dependency, backend numeric operation or generic inference rule is
needed.

Strings, null/pointer/resource/class/slice/array/struct/vector/mask constants,
unresolved type parameters, members, parameters/results, exports, attributes,
macros, value generics, modules and user-function CTFE are excluded.

See [language rules](../language/constants.md),
[evaluator architecture](../architecture/constant-evaluation.md), and
qualification.
