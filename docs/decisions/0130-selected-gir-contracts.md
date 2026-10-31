# 0130 — Selected, reproducible GIR contracts

Status: implemented and qualified for the finite profile in `tools/gir/README.md`.

GIR is an optional explicit foreign declaration input, not Astra's native object
model. The importer emits typed VAPI, native consuming helpers, a checked C
bridge and a versioned descriptor. Existing native ownership and foreign cleanup
authorities remain responsible for Resource borrows, full results and release.

Selection is per namespace/version/object/member. Unsupported selected shapes
fail closed with source coordinates. No type is inferred from pointer width.
Exact header signature assertions and actual GObject reflection independently
check what XML alone cannot establish. Metadata input, generator, package and
target identities bind generated bridge symbols as well as normalized products.
Generated header release assertions and runtime GLib release checks reject a
selected GObject package/header/runtime mismatch before type admission.

The first executable client imports installed GObject ref/unref and a real local
subclass's constructor, methods, integer/UTF-8 properties and signal. A full
Object receiver at unref crosses a generated native helper and is released by
the existing cleanup path; general consuming C arguments are still unsupported.
Transferred strings, borrowed object returns, arbitrary callbacks and broader
GIR constructs remain outside this profile, with explicit refusals.

Independent generation/verification is part of the recipe. Ordinary handwritten
VAPI retains its existing trust contract; it is not implicitly authenticated by
an adjacent descriptor. The maintained qualifier tests malformed XML, unsupported
types/annotations, transfer/ctype/parent/version conflicts, duplicate symbols,
wrong physical C signatures, wrong runtime properties, product corruption and
stale compiled bridges, restoring and rerunning valid artifacts afterward.
