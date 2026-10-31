# ADR 0002: Independent Astra identity

Status: accepted for development in ASTRA-CHARTER-1; public naming provisional.

## Decision

| Role | Name |
| --- | --- |
| Language/project | Astra |
| Repository | `astra-lang` |
| Meson project | `astra` |
| Compiler executable | `astrac` |
| Source extension | `.astra` |
| Implementation namespace | `Astra` |

Astra starts with fresh Git history and an independent architectural lineage.
It is not another Vala LLVM backend, llvm-v3 inside Vala, a Vala-compatible fork,
a GObject-native language, a `valac` wrapper, or a port of frozen LLVM-v2.
No fork relationship or Vala/LLVM-v2 history is introduced.

## Consequences

The local checkout directory need not match the canonical repository name.
The public/trademark status of “Astra” remains explicitly provisional pending
a later proper name/trademark collision review. This is not clearance, and it
does not block canonical use during development.
