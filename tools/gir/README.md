# Bounded typed GIR import

`import.py` is the explicit optional GIR tool. It uses Python's XML parser and
the installed `pkg-config`; ordinary `astrac` use gains no GIR dependency.
The first profile is GNU x86-64 Linux LP64, named GObject classes, copied `gint`,
full object constructors/results, borrowed receivers, copied UTF-8 results,
integer/string properties, and last-phase `int(int)` signals. Selection is
explicit; unselected declarations are not imported. This is not a general GIR,
GTK, callback, array, union, varargs, boolean or asynchronous binding generator.

The maintained executable example uses installed `GObject-2.0.gir` and
`tests/ecosystem-abi-8/AstraFixture-1.0.gir`, matching the real C subclass in
that directory. The profile supplies exact namespace versions, nominal C/GType
identities, parents, headers and selected member names. Unknown selected
annotations/types, missing/conflicting transfer/nullability contracts and
unsupported shapes reject with GIR file/line/column diagnostics. XML entities
and DTDs are rejected without reading external resources.

Generate in a fresh external directory, then independently verify the products:

```sh
python3 tools/gir/import.py --profile tests/ecosystem-abi-8/gir-profile.json \
	--gir /usr/share/gir-1.0/GObject-2.0.gir \
	--gir tests/ecosystem-abi-8/AstraFixture-1.0.gir \
	--output "$PM_CODEX_BUILD_DIR/gir-bindings"
python3 tools/gir/import.py --profile tests/ecosystem-abi-8/gir-profile.json \
	--gir /usr/share/gir-1.0/GObject-2.0.gir \
	--gir tests/ecosystem-abi-8/AstraFixture-1.0.gir \
	--verify "$PM_CODEX_BUILD_DIR/gir-bindings"
```

Products are `bindings.vapi`, `bindings.astra`, `bindings.c`, and `contract.json`.
Add `--policy-attributes` to generation and verification to emit canonical
`GObjectImport` callable declarations and a fifth product, `bindings.h`, with
the actual C bridge prototypes. Include the generated directory when compiling
the bridge. The selected mode participates in the ABI identity and product
hashes; changing modes requires regeneration. The legacy default retains its
existing `CCode` entry path. Both use the same runtime and ownership contracts.
Pass the VAPI with `--vapi` and the generated Astra file as an ordinary source.
Compile/link the generated C bridge, selected provider, and optional
`gobject.c`, `gobject-signals.c`, `retained.c` support objects explicitly. The
complete maintained commands, both host C ABI and memory controls, and exact
outputs are exercised by:

```sh
python3 tests/ecosystem-abi-8/gir-check.py "$PM_CODEX_BUILD_DIR/astrac" \
	"$PM_CODEX_BUILD_DIR/ecosystem-abi-8/gir"
```

The VAPI enters Astra's existing typed foreign boundary and its independent
Checked/Core/CFG/SSA/CABI verification. A GIR consuming `Object.unref` becomes
a typed native helper whose owned parameter uses the existing cleanup contract;
there is no new C consuming-parameter ABI. Full object results acquire exactly
one foreign duty. Transfer-none strings are copied explicitly into a foreign
UTF-8 snapshot; no borrowed pointer escapes. Properties use `_property_` names
to distinguish them from methods. Signal source handles weakly name the emitter;
the retained connection acquires its own strong ref.

C `_Generic` assertions check the actual selected header signatures. Compile-time
GLib release assertions and runtime version checks bind the selected exact
GObject package release before GType admission; mismatched versions fail closed.
Runtime
admission checks real GType names/parents, property types/access, and signal
payload/return/phase before bridge operations. This is necessary because GIR
self-description cannot establish the actual C library ABI. Scalar admission
failure returns `INT32_MIN`, owner/snapshot failure returns null. The selected
fixture reserves that scalar failure value. Cleanup still consumes its duty if
other contract admission fails.

The contract binds the input/profile/importer hashes, package versions, typed
surface, target profile and product hashes. Every generated bridge symbol
includes the full ABI input identity; stale C bridge substitution fails to link.
Reimporting to independent directories and reversing GIR argument order produces
identical bytes. Always run `--verify` before compilation: plain `--vapi` is a
general user-supplied declaration facility and does not authenticate a generator
manifest. Hashes establish consistency, not package signing or adversarial
provider trust.

The qualified combined debug recipe uses Clang C objects with `-gdwarf-4`, matching
Astra's explicit DWARF 4 profile. Earlier GCC C call-site and Clang DWARF 5 string
offset decoder failures remain in Surge 8 runtime evidence; no universal mixed
compiler debug compatibility is claimed. GCC separately qualifies the real
GObject adapter, C guards and native applications.
