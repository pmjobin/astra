# Local variables

Local declarations have either an explicit type or a type inferred from their
initializer:

```astra
Lab explicit_result = transform(input);
var inferred_result = transform(input);
```

Both are first-class source forms and require initializers. Explicit types
provide ordinary destination context; `var` checks its initializer without that
context and infers once. Later assignment follows the same fixed type and
ownership rules. Names are unavailable in their own initializer, and existing
duplicate/shadowing checks apply across nested local scopes.

See [local inference](local-inference.md) for exact types, numeric defaults,
ownership, diagnostics and the intentional reservation of `var`.
See [ownership](ownership.md) for moves, cleanup, release and replacement.
Parameters, results, fields, properties and foreign declarations remain
explicitly typed. [Named compile-time constants](constants.md) use `const NAME =
expression;` or `const Type NAME = expression;`, with no runtime initialization or
storage. Runtime immutable bindings remain undecided.
