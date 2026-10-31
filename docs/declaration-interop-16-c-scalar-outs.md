# Scalar reference channels and explicit produced counts

Selected `declarations-v1` members can use call-scoped borrowed native pointers to
`i32`, `u32`, `i64`, `u64`, `f32` and `f64`. Declare their logical direction with
`[ForeignChannel(parameter="value", direction="out|inout|in")]`. The C signature
uses a pointer to that exact scalar; an `in` reference is const in the header.
Boolean values continue to use copied bool inputs/results or copied record fields.
The existing unselected native pointer syntax and bounded foreign profiles retain
their admission rules.

These are typed value places. Pointer slots are mandatory; nullable scalar places
refuse. A scalar reference must use actual native `borrowed` ownership. It cannot
escape into a stored pointer or an unmanaged call argument. Core/CFG/SSA retain
that contract, and the native sidecar separately records the exact pointee, beyond
its physical PTR representation. Immutable pointer parameters remain direct
noescape inputs when building dereference places, rather than becoming unrestricted
pointer-copy temporaries.

Input and inout values are captured into private scalar scratch storage. Out
places are initialized to zero after the scalar pointer checks. On checked native
failure, inout values remain unchanged and out values stay empty. Successful
publication follows native receiver/argument hold retirement, then scratch storage
is retired. A result slot must be distinct from scalar parameter places; that
alias refuses before clearing either value. Input and inout snapshots precede
initialization of out parameters. Aliased parameter outputs publish in declaration
order, using their separate native scratch places.

An output byte channel can now name an actual output count parameter:

```astra
[Foreign]
[ForeignChannel(parameter="output", direction="out", produced="produced")]
[ForeignChannel(parameter="produced", direction="out")]
bool fill(borrowed u8[] output, borrowed int* produced) { /* native algorithm */ }
```

The count is an exact signed i32 out reference; capacity is an input count or the
intrinsic view length. The bridge checks `0 <= produced <= capacity` before
publishing bytes, scalar outputs or an owner result. The native method result is
independent of that count. Existing `produced="result"` continues to require an i32
native result.

Constructors and object-returning methods use the same output path. Their completed
native root remains provisional through count validation and wrapper conversion.
Invalid output counts or wrapper allocation failure retire that root once, leave
owner outputs null, and publish no mutable bytes or scalar result. Native
construction-context and unique/shared lifetime authority stay unchanged.

The independent/generated-header C matrix exercises all six pointer scalar types,
bool results alongside an explicit count, input snapshots, checked inout rollback,
negative/excess counts, constructor and object-result composition, and wrapper
allocation rollback at O0/O1/O2 for unique/shared roots. Whole-executable Valgrind
runs and detached pointee/noescape/publication/bounds mutations check the same
mechanism. This is an intermediate M16 slice; checked constructors and the
remaining imports, callbacks, personalities and qualification gates remain active
work.
