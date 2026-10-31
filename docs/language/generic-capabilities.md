# Generic capabilities

The named operator/Ownable capabilities below keep their separate meanings.
Current generic Class/member/record and structural `owned T` composition follows
[structural generics](structural-generics.md); the original GEN-CAP component's
Class/member exclusions below are historical, not current blanket restrictions.

GEN-CAP-1 adds explicit requirements to top-level native generic functions:

```astra
T add<T>(T a, T b) where T : Numeric {
	return a + b;
}

bool less_or_same<T>(T a, T b) where T : Eq, Ordered {
	return a == b || a < b;
}

T choose<T, U>(T a, T b, U token)
	where U : Eq
	where T : Ordered
{
	if (token == token && a < b) { return b; }
	return a;
}
```

After the parameter list and before the body, zero or more clauses follow:

```text
where-clause := "where" type-parameter-name ":" capability-name ("," capability-name)*
```

Use one clause per constrained parameter. `where T : Eq where T : Ordered`
rejects; write `where T : Eq, Ordered`. Repeated capabilities, unknown parameters,
unknown capabilities and empty/trailing lists reject. Clauses may appear in any
parameter order, which is retained in diagnostics and dumps. `where` is contextual
at this position, preserving its existing uses as an identifier elsewhere.

The capability namespace is separate from types, values and members. Its only
names are the exact, case-sensitive compiler-owned `Eq`, `Ordered`, `Numeric`,
`Bitwise`, `Shift`, and `Ownable`. There are no user capability declarations or
source Copy/Move constraints. Unconstrained and value-capability parameters retain
implicit `GEN1_PLAIN_COPY`. Explicit Ownable selects OWNABLE transport without
copy authority; it cannot combine with value capabilities on the same parameter.
See [generic ownership](generic-ownership.md) for the separate concrete matrix.

## Operators and matrix

| Capability | Authorized operations | Exact shape |
|---|---|---|
| Eq | `==`, `!=` | T × T → bool |
| Ordered | `<`, `<=`, `>`, `>=` | T × T → bool |
| Numeric | binary `+`, `-`, `*`, `/` | T × T → T |
| Bitwise | `&`, `\|`, `^`, `~` | T × T → T; ~T → T |
| Shift | `<<`, `>>` | T × concrete IntegerType → T |
| Ownable | Explicit owned transport, one incoming-owner local, call-scoped borrowing | Finite exact Resource/Class contracts; no plain-copy T authority |

| Concrete type | Eq | Ordered | Numeric | Bitwise | Shift |
|---|---|---|---|---|---|
| bool | yes | — | — | — | — |
| i8 | yes | yes | yes | yes | yes |
| u8 | yes | yes | yes | yes | yes |
| i16 | yes | yes | yes | yes | yes |
| u16 | yes | yes | yes | yes | yes |
| int / i32 | yes | yes | yes | yes | yes |
| u32 | yes | yes | yes | yes | yes |
| f32 | yes | yes | yes | — | — |
| f64 | yes | yes | yes | — | — |
| void* | yes | — | — | — | — |
| All admitted numeric vectors | — | — | — | — | — |
| All admitted boolean masks | — | — | — | — | — |

All these types retain unconstrained GEN1_PLAIN_COPY eligibility. A type must
satisfy every listed capability, including constraints on parameters unused in
value signatures or bodies. The first unsatisfied requirement in clause/list
source order is reported. Numeric + Bitwise, Ordered + Bitwise and Numeric +
Shift admit integer scalars; Eq + Ordered also admits f32/f64.

There is **no implication**. Ordered does not grant Eq; Numeric grants neither
ordering nor equality. Eq grants no boolean logic or bitwise operations on T.
Comparisons return concrete scalar bool, so their results work with `if`, `&&`
and `||`. T/U operands cannot mix, regardless of matching constraints or eventual
concrete arguments.

Numeric includes unsigned types and therefore grants no unary minus. No named
capability grants unary plus, `%`, `!`, casts, null, generic member access,
address-of, dereferencing or indexing. `a + 1` with a:T still rejects: generic
literals cannot be contextualized to constrained T. Supply a T parameter instead.
Shift counts may be int, u8 or any other concrete scalar integer expression;
another type parameter is never a valid count. Width-dependent invalid counts
retain runtime traps after specialization, including literal counts in generic
operations whose width is unknown at definition time.

## Definition-time authority and forwarding

```astra
bool inner<T>(T a, T b) where T : Eq { return a == b; }
bool outer<T>(T a, T b) where T : Eq { return inner<T>(a, b); }
```

Removing outer's Eq requirement rejects its definition even if every root call
uses int. An Ordered-only parameter cannot be forwarded to inner. Known explicit
requirements must contain every callee requirement; the compiler does not ask
which concrete types currently happen to inhabit those constraints. Unused
invalid definitions reject; unused valid definitions generate no instances.

An unsatisfied call reports, for example:

```text
type argument 'i16<8>' does not satisfy capability 'Eq' required by type parameter 'T' of generic function 'same'
```

No runtime evidence is passed. Exact capability operations survive through
parameterized Core and specialize to ordinary concrete operations before CFG.
Integer arithmetic keeps wrapping and divide-zero traps; f32/f64 division by zero
keeps IEEE infinity/NaN behavior. Floating comparisons retain NaNs and signed
zero, with no fast math or FMA contraction. Signed and unsigned ordering and right
shifts remain distinct. Numeric promises operation availability and shape,
without imposing uniform arithmetic laws.

Concrete properties/methods may call constrained generics. Generic bodies may
use concrete properties/methods/fields and concrete owned Resource/object
parameters independently of T; exact member identity and cleanup order persist.
A PLAIN_COPY T remains non-owning. Ownable permits `owned T` parameters/results
and explicit move, plus the finite Q11A borrowed T and Q11E incoming-owner local contracts. There are
no generic classes/methods/properties, parameterized pointer/slice/array constructors,
structural inference or user-defined specialization rules.

Vectors remain plain-copy arguments but do not satisfy named capabilities:
vector equality returns `bool<N>`, while Eq requires bool; vector arithmetic's
operator set differs by element family. Associated output types, vector
capabilities, user/interface capabilities and witness semantics remain deferred.

See [generic functions](generic-functions.md), [IR](../ir/generic-capabilities.md),
[ADR 0057](../decisions/0057-explicit-generic-capabilities.md), and
qualification.

## Generic native structs

GEN-STRUCT-1 permits Pair<T,T> locals inside constrained functions. A projection such as p.first retains the exact T token, so Ordered and other accepted requirements continue authorizing operations on that leaf. The aggregate itself gains no capability. Generic struct declarations have fields only and no where clauses. See [generic structs](generic-structs.md).

## Ownable

Ownable authorizes the explicit ownership domain, independently of future ordinary
Move or aggregate Copy semantics. It grants no Eq, Ordered, Numeric, Bitwise or
Shift operation, and none of them grants Ownable. Resources and native ClassTypes,
including empty/no-deinit classes, satisfy it. Scalars, vectors, void*, typed
pointers, slices, arrays and all structs reject. Exact requirement forwarding and
the same capability symbol namespace apply. [GEN-OWN-1](generic-ownership.md)
retains no runtime evidence.

## Local struct copy is separate

[Whole native struct copy](struct-copy.md) uses the shared recursive
CopyabilityAuthority, without adding a source Copy or Move capability.
GEN-COPY-1 extends default GEN1_PLAIN_COPY transport to eligible copyable
records and proves parameterized copies from exact scoped premises. It derives
none of Eq/Ordered/Numeric/Bitwise/Shift and adds no public capability.
Ownable continues to mean explicit ownership support. See
[copyable generic values](generic-copyable-values.md).

## Inferred calls

[Generic call inference](generic-inference.md) identifies exact arguments before
this capability authority validates them. `minimum(a,b)` infers T from a/b, then
requires Ordered. The same applies to Eq, Numeric, Bitwise and Shift. Constraints
do not generate candidates or imply each other. Inside a generic definition,
`minimum(a,b)` may propagate exact outer T, but T must explicitly establish Ordered
just as `minimum<T>(a,b)` requires. Missing authority is a capability diagnostic,
not an inference failure; unused definitions remain checked once.
