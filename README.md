# Astra

Powerful abstractions, low-level control, and code you can read without consulting the Rosetta Stone.

This repository begins the self-hosting transition. The complete `astrac` compiler
is still the repaired Vala implementation in `bootstrap`. The canonical
Astra compiler source belongs in `compiler/`; the source/diagnostic, lexical, typed
syntax and presemantic binding components now execute in Astra. Type checking, IR and backends remain in Vala.

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

The [binding component](compiler/semantic/README.md) provides Astra symbol, scope,
reference and native query APIs with the focused `binder-component-check` target.

The [lexer component](compiler/syntax/README.md) has an explicit compiler-selectable
batch test and the Meson `lexer-component-check` target.

The [source component](compiler/source/README.md) has an explicit compiler-selectable
differential test and the focused Meson `source-component-check` target. Regenerate
an existing Meson build after adding targets. Set `qualification_runtime` to the
desired external receipt directory when using that target. Detached white-box
test compilers use the project's ordinary warning policy; `astrac` itself always
enforces warnings as errors. Use a separate build directory for those helpers.

[seed.lock.json](bootstrap/seed.lock.json) records the actual development C0 hash,
source revision, flags and dependencies. Its inherited RC2 version banner does
not represent a new RC2 qualification. Full post-migration registry and self-hosted
bootstrap equivalence remain future work.

The donor is the separately preserved `astra-bootstrap` project at
`61d1529956369770fc817563a43b0038b852ab90`. Its history and historical qualification
remain distinct from this repository. See [bootstrap provenance](bootstrap/provenance.json).
Historical receipts containing private machine paths are retained in the private
archive; they are not new qualification results for this tree.

Licensed under **Apache-2.0 WITH LLVM-exception**; see [LICENSE.txt](LICENSE.txt).
