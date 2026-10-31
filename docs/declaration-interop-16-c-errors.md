# Checked native errors and C publication

A selected native method with `throws Fault` declares an explicit mapping:

```astra
[Foreign(error_domain="16", errors="BadInput=-1601,Fault=-1600")]
int read(int mode) throws Fault { /* actual native implementation */ }
```

The domain is a positive signed 32-bit integer. Each case names an actual native
exception type and a distinct negative signed 32-bit status. Cases appear from
specific to general; the final case is the exact declared throws bound. That final
case covers every remaining subtype, including private exceptions implemented in
opaque producer units. Unknown types, unrelated types, unreachable cases,
duplicate statuses and missing fallback authority refuse before emission.

The immutable common descriptor retains the mapping and native bound. Each stage
checks it against its actual callable and class graph; the detached native verifier
uses copied class ordinals and ancestry. Physical wrappers call the existing native
exception ABI, inspect its exception pointer before reading the success slot, map
the dynamic type and retire the original exception once. Native exceptions do not
unwind through C. Source parameter cleanup retires consumed inputs on checked
failure, and no staged mutable-byte output is published on that path.

The C return value is the status. Optional caller-owned `astra_foreign_error`
storage receives the same code and declared domain. Built-in pointer/count,
allocation, conversion and context refusals retain domain zero. Ordinary success
clears both fields. The generated SDK includes named domain/status constants and
`astra_foreign_error_clear`, an inline reset for this allocation-free record.
There is no allocated foreign error object to release; the native exception has
already been destroyed when the call returns.

`[Foreign(null_status="1")]` on an explicitly nullable owned native-object result
returns the declared positive status for a null native result and zero for a
non-null result. Error storage remains empty for both nonfailure outcomes. A
negative null status or a null status on an incompatible result refuses.

Inputs are validated before ownership transfer. Native success values and output
conversions stay provisional while receiver/argument holds retire. Only then are
scalar/POD outputs, mutable bytes and independent owned results published. An
owned native result contributes its C ownership duty at publication; a cached
wrapper does not expose that future duty during destruction reentry. Private
scratch storage remains alive until mutable output publication finishes. A native
state change is not rolled back merely because a later foreign conversion fails.

The independent C matrix covers unique/shared service and object roots, scalar
integer/FP and mixed POD success slots, void calls, staged byte outputs, owned
bytes/text/objects, consumed-input failure, dynamic subtype fallback, optional
error storage and positive nullable-result status at O0/O1/O2. Shared receiver
last-release reentry observes the empty output slot before publication. Eight
whole-executable Valgrind runs and detached bound/ABI/status mutations qualify this
intermediate slice. Checked constructors, scalar out parameters, C Class imports,
callbacks, COM/GObject mappings and the remaining M16 gates are still outstanding.
