# Pointers

Astra distinguishes [opaque raw void*](raw-pointers.md) from
[typed data pointers](typed-data-pointers.md). Typed pointers include supported
integer/f32 pointees and [native structs](typed-struct-pointers.md), with exact
pointee identity, nullable values, and non-owning [lexical borrows](borrows.md).

Scalar `*p` is a storage Place; struct `p->field` projects a field Place. Direct
local address-of makes storage observable and prevents ordinary scalar
promotion of that local. Both access paths remain coherent across aliases and
native calls. Vector lane extraction remains a value operation.

The typed-data-pointer guide specifies supported syntax, null traps, native PTR
transport, alignment by construction, and deferred pointer/foreign-memory forms.
