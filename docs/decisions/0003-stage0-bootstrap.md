# ADR 0003: Ordinary system Vala for Stage 0

Status: accepted in ASTRA-CHARTER-1.

## Decision

Implement Stage 0 in Vala, compiled by the ordinary upstream/Fedora system
`valac` through Meson, Ninja, and a native C toolchain. Use system pkg-config,
GLib/GObject development packages, and system LLVM development packages.
The exact qualified host is recorded in [toolchain.md](../toolchain.md).

The executable is `astrac`. This milestone provides help/version output and
explicit diagnostics for unsupported source compilation. LLVM construction and
verification run in a separate internal smoke executable using Meson's native
test mechanism. Tests are offline and deterministic.

## Rationale and consequences

Vala provides a practical founding implementation language without making its
semantics Astra's language specification. Generated C is an incidental host
build artifact and is never Astra's semantic authority (ASTRA-I1).

GLib/GObject support the Vala host implementation only. They introduce no target
runtime dependency or native object model (ASTRA-I2, ASTRA-I7). There is no Astra
runtime library. Self-hosting remains a future maturity milestone.

There is no dependency on modified LLVM-v2 `valac`, a Vala source tree, parser
generator, third-party test framework, package manager, or separate Python
build/test script. Meson's own packaged implementation dependencies remain
Meson's concern. No bootstrap source is ported from Vala or LLVM-v2.
