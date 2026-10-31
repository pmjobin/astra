# M16 typed GIR round-trip

`tools/gir/import.py` now accepts the explicit
`astra-gir-declarations-profile/1` profile. The historical `astra-gir-profile/1`
normalizer and its accepted/refused shapes remain unchanged. The new profile pins
namespace/version, SDK C/GType/parent identities, headers, selected members and
checked error mapping. It generates typed GObjectImport declarations and a hashed
contract, with no producer bodies or application adapters.

Generated declaration-driven GObject SDK comments retain byte/text kind, UTF-8
conversion, bounded output direction/produced count, boxed native provenance and
checked domain/status metadata. They use GI's supported namespaced
[attributes](https://gi.readthedocs.io/en/latest/annotations/giannotations.html#attributes),
which survive GIR scanning and typelib compilation. Standard GIR facts continue
to carry actual scalar/pointer types, transfer, nullability, array length,
callback scope/closure and checked `throws` effects. Missing or conflicting facts
reject rather than guessing text encoding, ownership or retention.

The importer checks selected SDK identities and public C shapes, reconstructs
properties from selected exact typed accessors, emits bodyless checked methods,
and copies boxed fields with their original ordinal/member names. Callback
userdata remains explicit and call-scoped. Independent owned results, counted
embedded-NUL text, explicit terminated strings, scalar references, bounded caller
storage, typed foreign objects and nullable results retain their native channel
contracts. Imported records receive fresh nominal source names while retaining
the exact boxed SDK C/GType/free binding and scalar field layout.

The portable round-trip recipe builds a fresh five-variant native SDK, scans and
compiles each GIR/typelib, imports each generated GIR twice, verifies deterministic
products, compiles a native Astra consumer, and links it against the compiled
producer library. The consumer invokes actual native algorithms through imported
properties, scalar/void callbacks, checked references, buffers, UTF-8, mixed/closed
generic boxed records and owned object channels. An independent C observer checks
exact native session/object retirement. Two clients run under Valgrind. Mutants
cover lost ownership, encoding, checked effects/status, callback scope/closure,
array count/produced facts, GType and boxed bool storage, unknown facts, generated
product drift and DTD/entity refusal.

An absent `parameters` element means an empty parameter list for constructors
and signals. Methods still require their exact borrowed instance parameter;
callbacks require explicit userdata. Duplicate groups, a signal instance
parameter and unknown group attributes reject. Empty signals retain the complete
synchronous GClosure retirement contract. The `empty-parameters.py` recipe uses
the real scanner and typelib compiler, checks equivalent explicit-empty bindings,
runs O0/O1/O2 consumers and retains memory and malformed-input controls.
