# Struct pointers

[Native struct pointers](typed-struct-pointers.md) use the same
`TypedPointerType(pointee)` architecture as [scalar data pointers](typed-data-pointers.md).
Their exact nominal pointee identity, nullable equality, lexical borrow rules,
`p->field` Places, aliasing, and null traps retain the accepted TPTR-1 behavior.
Whole-struct `*p` values remain unsupported.

The canonical [struct-pointer guide](typed-struct-pointers.md) contains grammar,
examples, and the existing RHS-first field-assignment evaluation rule.
