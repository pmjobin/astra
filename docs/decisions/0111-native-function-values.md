# 0111: Typed native function addresses

`Fn<Result, Arg...>` denotes a nonnull native code address with an exact,
nonthrowing signature. The finite profile admits zero to four copied numeric
scalar or bool arguments and a copied numeric scalar or bool result. Signature
identity includes exact integer widths and signedness. It excludes ownership,
borrowed data, aggregate, async and checked-effect channels. Unsupported forms
are diagnosed rather than cast to a similar pointer shape.

A named native function can initialize, enter as an argument, or return as an
`Fn` value. Locals and parameters carry that value, including copies, assignment
and branch merges. Calling a typed local uses the local's code value even when
a global function has the same spelling. The pre-existing nominal callable
Class resolution rule remains unchanged. Namespace resolution and source-order
rules apply to named address creation.

Checked, Core and CFG address/call nodes preserve exact signature and callee
identity. SSA represents address constants and indirect calls, with ordinary
definition and dominance checks for transported code values. The native model
distinguishes a typed code pointer from an untyped data PTR and records every
indirect invocation site. LLVM builds the actual native call type and calling
convention and independently checks its emitted code operand and arguments.
No environment allocation or cleanup channel accompanies a bare `Fn`.

An `export(C)` function still has a native implementation and a separate C
wrapper; its native body may be bound. `Fn` itself cannot cross a C boundary.
Named synchronous C callbacks retain their separate provider contract. Owned
environments use [decision 0112](0112-explicit-owning-closure-values.md), not an
untyped cast or implicit stack capture.

Qualification lives in `tests/language-runtime-4/callable-check.py` and
`callable-proof.vala`, including independent C clients, an allocation observer,
malformed stage models and public optimization routes. Qualification outcomes
are recorded separately in the Surge-4 validation inventory.
