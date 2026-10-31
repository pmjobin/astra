# Compiler-backed language tools

Install `astra-lsp` beside `astrac` with Meson. The server uses Python 3.10+ and
standard stdin/stdout JSON-RPC framing; stdout is reserved for protocol messages.
It invokes the selected compiler's `--tooling-index` and `--format` commands,
without a second Astra parser. The protocol follows
[LSP 3.17](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/).

```sh
astra-lsp --compiler /opt/astra/bin/astrac
```

The selected editor profile supports initialization/shutdown, local file URIs,
UTF-16 positions, full document synchronization, compiler semantic diagnostics,
hover, definitions, references, completion and formatting. Changes affect
temporary compiler inputs; the server never saves or rewrites editor sources.
Document versions must increase. Invalid or stale changes leave the previous
document intact. A cancellation request can cancel queued and active compiler
requests. Frames, source counts, source sizes and compiler time are bounded.
Malformed JSON reports a protocol error; unusable framing terminates cleanly.

Place an optional `astra-project.json` in the workspace root:

```json
{
	"sources": ["library.astra", "main.astra", "other.astra"],
	"vapi": [],
	"native_modules": []
}
```

Paths are explicit and relative; parent traversal rejects. Open `.astra` files
join that source set, and their unsaved text replaces disk contents in the
compiler snapshot. Without a project file, only explicitly opened documents are
selected. VAPI and native units use the existing compiler interfaces. The
configuration cannot select executable commands or run build hooks. Reopened
sources and watched-file notifications refresh checked data.

`--tooling-index FILE...` emits `astra-tooling/1` JSON with byte-based source
ranges, resolved declaration identities, selected reference bindings and original
semantic diagnostics. It stops at checked semantics; successful indexing is not
an LLVM, link, ownership-flow or release acceptance result. Run `astrac --check`
and ordinary compilation for those later stages. Editor navigation currently
covers declarations and checked value reads, calls, receiver uses, selected
fields/properties and function addresses. It does not promise complete type-name,
assignment or every desugared-operation references. Rename is deliberately not
advertised. Local completion uses function extents and is a suggestion list,
not an independent lexical-visibility or ownership proof.

Public policy inspection uses the same checked compiler model:

```sh
astrac --explain-semantics library.astra main.astra
```

It describes unique/intrusive ownership, explicit acquisition and assignment
movement, declared Monitor/Singleton/ThreadBound/Actor constraints, allocation
policy and existing explicit C boundaries. Runtime descriptors remain opt-in.
This is the current source-policy view, not a claim that new foreign adapters or
all October policies have already been implemented.

For the installed editor profile, run the source-distribution recipe
`tests/interop-tooling-14/editor.py PREFIX/bin/astrac EXTERNAL_OUTPUT --prefix PREFIX`.
It copies the installed A130 project into an isolated workspace, uses the
installed server/extension with a fresh VS Code user/extension directory, and
checks actual editor navigation, unsaved diagnostics and formatting. The same
repaired source executes at O0/O1/O2 and selected unsuppressed Valgrind. Original
sample files and existing editor settings remain untouched.

## VS Code client

`tools/lsp/editor` contains a dependency-free VS Code extension that launches the
server and connects diagnostics, hover, definitions, references, completion and
formatting to the editor. Configure these machine-scoped settings for an
installed toolchain:

```json
{
	"astra.compilerPath": "/opt/astra/bin/astrac",
	"astra.serverPath": "/opt/astra/bin/astra-lsp"
}
```

For development, `astra.serverPath` can point to `tools/lsp/astra-lsp.py`;
`astra.pythonPath` selects its Python interpreter. Launch the client with VS
Code's `--extensionDevelopmentPath` pointing to that directory. The extension
does not install packages or execute workspace-provided commands. Normal
compilation still uses explicit provider/link inputs.
Meson also installs the client at `PREFIX/share/astra/editor`, which can be
selected with the same VS Code development-extension option outside the checkout.

The [example project](../../examples/interop-tooling-14/editor-project/main.astra)
combines native Shared ownership, namespaces and a same-named function in a
different namespace. Its protocol recipe is `tests/interop-tooling-14/lsp.py
ASTRAC EXTERNAL_OUTPUT`. Its actual editor recipe is
`tests/interop-tooling-14/editor.py ASTRAC EXTERNAL_OUTPUT`, which requires a
working display and installed VS Code. Both use isolated sources/settings and
retain exact command/message receipts externally. The editor recipe checks
unsaved diagnostics and repair, UTF-16 navigation, policy hover and formatter
idempotence while verifying disk sources remain unchanged.
