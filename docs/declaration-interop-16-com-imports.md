# M16 typed COM import prerequisites

This document records the scalar import slice at `945480f4`. Its subsequent
[typed payload and export integration](declaration-interop-16-com-payloads.md)
extends the supported channels and directions. The pinned slice ledger retains
the original qualification identities.

The declarations-v1 COM interface form now accepts actual typed bodyless methods
and read/write properties with explicit checked error factories. An explicit
`init(borrowed void* unknown) throws Fault` acquires the declared interface through
IUnknown::QueryInterface. It does not construct a native Class. Imported owners
retain one actual COM interface reference and constructing-thread/apartment
context; native cleanup releases that reference and the private context carrier.

`ForeignComInterface` is immutable declaration data: nominal name, C prefix, IID,
optional single base, ordered requirements and native export-mapping names.
IUnknown occupies slots 0/1/2; own methods follow the inherited prefix. Properties
expand getter then setter. Logical booleans have explicit BOOL32 COM transport;
the internal C bridge retains C99 bool. Acyclic inheritance is bounded at 32,
requirements at 4096, and source roots/IIDs/prefixes are distinct. Every detached
stage checks its own declaration inventory, full binding identity and exact parent.

The native ABI retains explicit call-only IUnknown-query provenance on the raw
acquisition parameter. A same-width plain pointer cannot replace it. The C ABI
still describes the internal mechanical C entry, while the COM protocol describes
its separate IID/slot/signature transport. Generated C++ calls actual virtual
methods, converts scalars, stages reference/result outputs and maps HRESULT errors
to the declared native domain. Positive HRESULT method success becomes successful
native payload delivery. QueryInterface itself requires S_OK and a nonnull result.

That slice’s C++ import bridge supports i32/u32/i64/u64/f32/f64/bool, scalar
references and synchronous scalar/void callbacks, including BOOL32 conversion and
exact user data. It pins the actual interface during dispatch. Counted bytes,
owned text, POD and general interface-valued channels still require bridge
implementation; emission rejects these explicitly. COM exports, common target
personalities and foreign metadata in opaque units remain pending. This is an
intermediate slice, not completion of G3 or M16.

The independent Windows producer declares its own IUnknown-derived interface
prototypes, inheritance, IIDs and BOOL32 callback. The native Astra consumer checks
methods, properties, callback results and shared state across the two interfaces.
The producer checks all method and callback counts, balanced references, destruction,
positive HRESULT payloads, null/absent interface failures and native error domains.
Five actual Windows executions cover every O0/O2 native/bridge pair plus O1.

The detached mutation suite releases upstream stages before checking inherited
mapping substitutions. It also rejects changed native/C ABI roots, omitted raw
IUnknown borrow provenance and an ordinary-valid LLVM query argument substitution.
Source negatives cover IID collisions, cycles, unknown bases, storage fields,
query ownership/signatures, callback retention/type and target mismatch. Earlier
build failures and their exact diagnostics are retained alongside qualification.
