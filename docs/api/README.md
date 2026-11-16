# Source-derived API documentation

The 28-A1 development pipeline uses the production lexer, syntax arena, Binder
and checked semantic model. API extraction stops before Flow/Core/CFG/SSA/LLVM.
It does not run examples, emit objects, invoke a linker or launch another parser.

From an explicit source root, supply every dependency as a relative source path:

```sh
astrac doc --format json --output /absolute/build/api.json lib/astra/base/order.astra
astrac doc --format html --output /absolute/build/api.html lib/astra/base/order.astra
```

The destination's parent directory must already exist. HTML is a single static
file with navigation, stable anchors, escaped Markdown and resolved contracts.
JSON uses [astra-api-docs/1](schema.md). An explicit standard-library-only
adapter can render an existing JSON artifact with
`python3 -B tools/docs/render.py api.json --output reference.html`; it preserves
Markdown verbatim and builds navigation and related links from structured IDs.
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
