# Astra

Powerful abstractions, low-level control, and code you can read without consulting the Rosetta Stone.

This repository preserves the complete `astrac` compiler as the repaired Vala
implementation in `bootstrap`. Astra compiler components will be introduced
separately as the self-hosting transition proceeds.

Shared Astra libraries are in `lib/astra`, native runtime implementations in
`lib/runtime`, and public foreign declarations in `lib/bindings`. Installed API
paths retain their existing names. Tests, examples, workloads and tools are shared.

Build with system Vala, Meson 1.11+, Ninja, GCC, GLib and LLVM 22:

```sh
build="$HOME/Workspace/codex/work/astra/build/developer"
meson setup "$build" "$PWD" -Dbuildtype=debugoptimized -Dwerror=true
meson compile -C "$build" astrac -j 4
"$build/astrac" --version
```

Use explicit production/test targets; the default graph includes hundreds of
independent white-box test compilers. Do not build the entire graph for routine
component work. Build outputs and temporary execution data stay outside source.

The donor is the separately preserved `astra-bootstrap` project at
`61d1529956369770fc817563a43b0038b852ab90`. Its history and historical qualification
remain distinct from this repository. See [bootstrap provenance](bootstrap/provenance.json).
Historical receipts containing private machine paths are retained in the private
archive; they are not new qualification results for this tree.

Licensed under **Apache-2.0 WITH LLVM-exception**; see [LICENSE.txt](LICENSE.txt).
