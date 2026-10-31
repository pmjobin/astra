# Offline Astra packages

`astra-pkg` composes existing explicit Astra sources, VAPI declarations, verified
native units and optional provider objects. It executes the installed `astrac`;
it adds no source language, native ABI, download service or install scripts.
Python 3.10 or newer is a tool dependency, never a generated-program dependency.

Each package has `astra-package.json`:

```json
{
	"format": "astra-package/1",
	"name": "measurements",
	"version": "0.1.0",
	"compiler": "0.0.3",
	"abi": "source+native-unit/1",
	"license": "Apache-2.0 WITH LLVM-exception",
	"sources": ["src/measurements.astra"],
	"dependencies": {"arithmetic": "0.1.0"}
}
```

Versions are exact three-component numbers. Version ranges, network registries,
automatic upgrades and install hooks are outside this format. Source packages
retain ordinary namespaces, generic specialization and ownership checking.
Separate native interfaces retain their existing compiler fingerprint and
[`astra-native-module/2` verification](../language/native-units.md); the package
version is independent of the native module schema.

Optional lists are `vapi`, `native_modules`, `objects`, `libraries` and `assets`.
Every file is explicitly relative to its package root; traversal, symlinks,
duplicate JSON keys, duplicate file roles and unknown fields reject. A native
unit's sibling implementation object must appear in `assets`, so it is installed
and hash-locked without also being passed as a duplicate linker object. An
ordinary external C provider belongs in `objects`. Licenses/notices can be
included in `assets`; the declared license describes the package author's grant.

Create a new library directory, then edit its source:

```sh
astra-pkg create arithmetic --name arithmetic --compiler-version 0.0.3 \
	--license 'Apache-2.0 WITH LLVM-exception'
astra-pkg lock --package arithmetic --compiler /opt/astra/bin/astrac
astra-pkg install --package arithmetic --prefix /tmp/astra-local \
	--compiler /opt/astra/bin/astrac
```

For a consumer depending on `arithmetic`, resolve from that prefix. Add
`--path /absolute/local/package` for each explicit development dependency. Paths
are command-line choices, never embedded in manifests or locks.

```sh
astra-pkg lock --package /tmp/consumer --prefix /tmp/astra-local
astra-pkg list --package /tmp/consumer --prefix /tmp/astra-local
mkdir -p /tmp/consumer-build
astra-pkg build --package /tmp/consumer --prefix /tmp/astra-local \
	-O 2 -g -o /tmp/consumer-build/program
/tmp/consumer-build/program
```

`astra-package.lock` binds every manifest and selected input byte, the complete
transitive graph, compiler binary SHA-256, compiler version and target/data layout.
Build, list and install recheck it. No stale lock is automatically rewritten;
after reviewing an intentional update, remove the old lock explicitly and run
`lock` again. A lock authenticates consistency with the reviewed local inputs;
it is not an author signature. Rebuilding the compiler requires fresh locks and
native unit artifacts even when the displayed compiler version is unchanged.

Installations live at `PREFIX/share/astra/packages/NAME/VERSION`. Existing
versions are reused only if their declared content has identical hashes;
different contents never overwrite an installed version. Moving the full prefix
preserves locks, because they contain identities rather than absolute paths.
Build outputs must be new paths outside every source package. Package tools do
not remove source, overwrite outputs, or execute package-supplied scripts.

The qualification recipe is `tests/interop-tooling-14/packages.py ASTRAC
EXTERNAL_OUTPUT`. It builds a transitive generic/C-provider project at public
O0/O1/O2, deletes its temporary producer source, installs and relocates the
dependencies, independently compiles/installs a native unit, and exercises
tamper/cycle/version/path/symlink refusals followed by restored execution.
This is a focused tool qualification; full Surge 14 release acceptance is
tracked separately in the campaign ledger.
