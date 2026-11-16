# Source-derived API documentation

The 28-A1 development pipeline uses the production lexer, syntax arena, Binder
and checked semantic model. API extraction stops before Flow/Core/CFG/SSA/LLVM.
It does not run examples, emit objects, invoke a linker or launch another parser.

The GNU/Linux native build uses a small launcher and two adjacent images named
`astrac.doc` and `astrac.native` (or the corresponding suffixed build names).
Keep all three files together. Both images contain the identical compiled Astra
object: the documentation image has no LLVM dependency, and its backend imports
are fatal guards. Normal compilation selects the complete LLVM-linked image.
This avoids LLVM startup allocations without calling LLVM from documentation.

`tools/docs/build.py --full` builds the native objects with explicit producer,
link manifest, O0/O2, build and runtime paths. Then `tools/docs/link.py` takes
that `--products` result, its `--identity` receipt, explicit `--mode O0 --mode O2`,
and fresh `--build`/`--runtime` paths to produce the paired CLI images.
The frontend-only build is a focused diagnostic product; final native checks use
the paired complete compiler. `tools/docs/preview.py` reproducibly generates the
real library, compiler-module and checked-example catalog pages from those images.

From an explicit source root, supply every dependency as a relative source path:

```sh
astrac doc --format json --output /absolute/build/api.json lib/astra/base/order.astra
astrac doc --format html --output /absolute/build/api.html lib/astra/base/order.astra
```

The destination's parent directory must already exist. HTML is a single static
file with navigation, stable anchors, escaped Markdown and resolved contracts.
JSON uses [astra-api-docs/1](schema.md). An explicit standard-library-only
adapter can render an existing JSON artifact with
`python3 -B tools/docs/render.py api.json --output reference.html`; it displays
the bounded safe Markdown subset, readable parameter/result/constraint sections,
and navigation and related links from structured IDs. The raw checked record is
available in a secondary expander.
The default [stylesheet](../../tools/docs/api.css) is authored separately from
the compiler. Pass `--stylesheet local.css` to embed an alternative in the single
standalone page; regeneration retains that explicit choice. Stylesheets are
limited to 128 KiB, and the page's content policy blocks external resources and
scripts. No compiler rebuild is needed to change the companion renderer's look.
This adapter never reparses Astra, compiles examples or invokes native tools. Basic browsing needs no JavaScript,
network, frontend framework, server or optional native providers. Outputs are
generated build artifacts. Keep authored comments and Markdown in Git.

Default output includes public declarations and empty documentation for public
declarations that have no comment. `--internal` includes internal/private APIs
with visibility labels. Source names must be relative without `..`; host
absolute paths do not enter the public schema. Input ordering is canonicalized
by the existing source-set owner. Existing non-generated output files,
symlinks, symlinked destination parents and traversal are refused.

See the [author guide](authoring.md), [Reference](../reference/README.md),
[Programming Guide](../guide/README.md) and [chapter map](../chapters.json).
See the [engineering findings](acceptance-status.md) for acceptance status and
limitations; the existence of these instructions is no test PASS.

The exact 27-D self-host baseline remains historical. [Release exceptions](../release-exceptions.md)
retain 27-B PARTIAL, lost original proofs and replacement C0 memory NOT_PASS,
alongside the owner's accepted provenance substitution. No release or deployment
is authorized by documentation generation.
