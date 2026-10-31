# Selected GObject import policy

`[GObjectImport]` names the existing explicit GObject/GIR C bridge at a typed
Source or VAPI callable. It requires an explicit nonempty `header`; `name`
selects the C symbol. Source functions have no body. Selected C transport
arguments retain their existing checked meanings. This profile is hosted
GNU x86-64 Linux LP64. Compile and link the bridge and SDK explicitly.

```astra
[GObjectImport(name="settings_read", header="settings-bridge.h",
	pointer_abi="i32-noescape")]
int read_setting(borrowed int* value);
```

The attribute records integration authority and does not open the named header,
infer a library, authenticate a provider or establish arbitrary pointer safety.
Use the [bounded GIR importer](../../tools/gir/README.md) with
`--policy-attributes` to generate this form from selected, verified GIR contracts.
Its `bindings.h` declares the actual bridge symbols. Run the importer with the
same flag and `--verify` before compilation. The legacy generator mode remains
available with its existing `CCode` declarations and contract identity.

GIR object owners remain nominal foreign Resource handles. Each full result/ref
acquires its own foreign cleanup duty; assignment moves and explicit ref helpers
retain. Borrowed receivers acquire none. Transfer-none text becomes an explicit
owned UTF-8 snapshot. The existing retained signal provider disconnects and
observes callback quiescence before native capture cleanup. See the
[GObject lifetime guide](gobject-interop.md). Native Class layout, native
Shared/Weak counts and foreign reference counts retain their separate meanings.

The admitted origin and ordered header/symbol identity survive checked semantics,
Core, CFG, SSA, native ABI and C ABI. Substituting the origin or dropping the
native inventory rejects; a hosted import cannot be relabeled as Windows or
freestanding output. Native-module declaration export refuses foreign callables
instead of serializing a declaration without its policy.

Qualification uses real installed GObject headers/runtime and an independently
compiled subclass, generated C signatures, real properties/signals, full-result
cleanup and copied text at O0/O1/O2. It retains version, signature, transfer,
nullability, product-tamper, stale-symbol, debug and unsuppressed Valgrind controls.
Separate Source spelling execution and all-stage mutation/restoration checks
cover the new entry path. These selected imports do not imply a general GIR,
GTK, arbitrary callback or asynchronous GObject binding generator.
