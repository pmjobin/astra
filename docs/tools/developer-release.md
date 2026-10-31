# Astra developer distribution

Astra is a stage-0 Vala compiler producing native LLVM objects. The selected
binary distribution is GNU/Linux x86-64 and requires its manifest's system
libraries, including LLVM 22 and GLib/GObject. These compiler dependencies do
not become dependencies of every generated program. Python runs the package
tool and language server. A host C toolchain links hosted executables and
explicit provider objects. The source distribution additionally requires
upstream valac, Meson/Ninja, C11 headers and LLVM 22 development files.

This checkout produces development distributions. The old RC1/RC2 campaign
promoter is retired; the inherited version banner is not a fresh release verdict.
The developer build manifest records source, compiler/runtime inputs, installed
file digests/modes and dependencies. Byte reproducibility is distinct from
behavioral and platform qualification.

## Private installation and first program

Choose the binary archive identified by the release manifest and verify its
SHA-256 against that manifest. Extract it into a new private directory:

```sh
archive=/absolute/path/to/the-identified-astra-archive.tar.gz
prefix="$PWD/astra-developer"
mkdir "$prefix"
tar -xzf "$archive" -C "$prefix" --strip-components=1
"$prefix/bin/astrac" --version
"$prefix/bin/astra-pkg" --version
"$prefix/bin/astra-lsp" --version
```

The entire prefix can move. Its tools locate their companions through the
prefix. No system prefix, package database or desktop configuration is modified.
Create `answer.astra` outside the installation:

```astra
int main() {
	int answer = 40 + 2;
	return answer - 42;
}
```

```sh
for level in 0 1 2; do
	"$prefix/bin/astrac" "-O$level" -g answer.astra -o "answer-O$level"
	"./answer-O$level"
done
"$prefix/bin/astrac" --check answer.astra
"$prefix/bin/astrac" --format answer.astra > formatted.astra
"$prefix/bin/astrac" --format --check formatted.astra
"$prefix/bin/astrac" --policy-registry
"$prefix/bin/astrac" --explain-semantics answer.astra
gdb --args ./answer-O0
```

Use a source breakpoint such as `break answer.astra:2`. Selected backed
aggregate fields, closure captures and async parameters have actual O0/O2
debugger witnesses. Optimized-away values remain unavailable; see
[source debugging](../language/source-debugging.md).

## Libraries, packages and editor

Supported source library and C/VAPI/header provider inputs live under
`share/astra`. Prebuilt support objects use `lib/astra/x86_64-linux` in the
portable build; a source build may choose another Meson `libdir`. Supply each
required Astra/VAPI and object/library explicitly. An installed provider source
does not select or link it.

Create and build an offline package outside every source package:

```sh
"$prefix/bin/astra-pkg" create consumer --name local-consumer \
	--compiler-version 0.0.3 --license 'Apache-2.0 WITH LLVM-exception'
cp answer.astra consumer/library.astra
"$prefix/bin/astra-pkg" lock --package consumer --compiler "$prefix/bin/astrac"
"$prefix/bin/astra-pkg" build --package consumer \
	--compiler "$prefix/bin/astrac" -O 2 -o "$PWD/package-program"
./package-program
```

For exact-version dependencies, transitive objects, integrity locks and
relocation use [packages](packages.md). Locks bind the compiler binary and all
input bytes. Deliberate compiler/dependency changes require reviewed fresh
locks and rebuilt native units, even with an unchanged displayed compiler
version. Package installation executes no scripts or network registry access.

`astrac --version` retains compiler/package version `0.0.3` and the inherited
milestone banner. Native units bind compiler fingerprints and GNU schema `/6`;
rebuild units when compiler identity changes, including older `/5` units.
The displayed version alone does not promise native ABI compatibility.

The real JSON-RPC server is `bin/astra-lsp`. VS Code extension sources live
under `share/astra/editor`; follow [the editor guide](language-server.md) to
select the compiler and open a multi-file project. CLI builds and checked source
ownership remain authoritative. Installed A129/A132 examples live under
`share/astra/examples/interop-tooling-14`. Their source-distribution qualification
recipes accept `--prefix` and compile all application inputs from the installation.

## Supported profiles and ABI boundaries

| Profile | Explicit choice and scope |
| --- | --- |
| Hosted GNU/Linux x86-64 | Native unique/Shared, strict numeric and bounded relaxed policies; explicit hosted providers |
| Linux no-libc | `--runtime=none`, authored startup/static linker; no hosted allocation/text |
| x86-64 no-OS QEMU | `--target=x86_64-none-elf --runtime=none`, authored startup/linker/MMIO/allocator; actual guest boot |
| AArch64 | `--target=aarch64-none-elf --runtime=none`; selected object inspection only |
| Cooperative async | Explicit virtual executor source/object |
| Linux async | Matching liburing >=2.15 and explicit timer/file provider/library; campaign uses 2.15 |
| Threaded/TCP/UDP | Explicit GNU Linux pthread/threaded/network providers and checked owner/domain rules |
| C | Selected typed scalar/POD/callback/ownership, approved union/C99 bool, opaque Class wrappers |
| GObject/GIR | Explicit adapter, GLib/GObject and GIR/typelib tools; selected stable wrappers and thread affinity |
| COM | Separate native Windows x64 in-process SDK profile; independently compiled clients, registration-free factory |

Native module schemas/compiler fingerprints are checked on import. Foreign
profiles have exact signature/identity/ownership checks and documented versions.
An upgrade must preserve or deliberately version contracts and rerun independent
clients. A package version alone does not grant ABI compatibility. Native object
addresses are not C/COM/GObject interface pointers, and native exceptions cannot
escape through those frames.

SH-4, self-hosting, physical boards, general COM marshaling/WinRT, automatic cycle
collection and generalized reactive graphs remain deferred or optional.
Historical LAZY-1 Q4 remains HELD/INCOMPLETE; current lazy semantics have separate
fresh-source qualification.

## Rebuilding, dependencies and removal

The source archive includes `tools/release/developer-build.py` and its ordinary
Meson recipe. It creates two independent source/build/install trees, disables
caches, uses fatal production warnings, relocates both installations and compares
every byte/mode. An existing liburing prefix is optional; no packages are installed.
See `tools/release/README.md` in the source archive for the exact invocation.

A source archive has no Git metadata. Build its production targets directly with
Meson; the two-build recipe above starts from an existing committed checkout.
Use separate absolute source, build and staging paths. The following matches the
optional worker/liburing profile when the declared dependencies already exist:

```sh
source=/absolute/extracted/astra-source
build=/absolute/task/build/source-rebuild
stage=/absolute/task/build/source-stage
uring=/absolute/existing/liburing-2.15
CCACHE_DISABLE=1 meson setup "$build" "$source" --buildtype=release --prefix=/opt/astra \
	--libdir=lib -Dwerror=true -Db_ndebug=false -Dhosted_concurrency=true \
	-Dlinux_async=true -Dpkg_config_path="$uring/lib/pkgconfig"
CCACHE_DISABLE=1 python3 - "$build" <<'PYTHON'
import json, subprocess, sys
from pathlib import Path
build = Path(sys.argv[1])
targets = json.loads((build / 'meson-info/intro-targets.json').read_text())
production = [row['name'] for row in targets if row.get('installed')]
assert 'astrac' in production
subprocess.run(['meson', 'compile', '-C', str(build), '-j', '4', *production], check=True)
PYTHON
meson install -C "$build" --no-rebuild --destdir "$stage"
"$stage/opt/astra/bin/astrac" --version
```

Omit the liburing path and choose `-Dlinux_async=false` for a build without that
optional provider. The full test-target build is separate from these installed
production targets. For byte comparison with an identified developer build, also use its
recorded C source/build prefix maps and exact tool/dependency identities; an
ordinary source build alone does not establish reproducibility.

`share/licenses/astra/LICENSE.txt` preserves the project grant.
`share/licenses/astra/THIRD-PARTY.json` records actual linked system-library hashes,
package versions/license metadata, stage-0 tools and optional liburing identities.
System shared libraries and the external liburing archive are not bundled.
`liburing-MIT.txt` preserves the selected inline headers' upstream MIT notice
from the [official liburing 2.15 license](https://github.com/axboe/liburing/blob/liburing-2.15/LICENSE).

For a shared-library load error, compare the host with the dependency manifest.
Missing provider symbols identify optional service objects/libraries that must
be supplied. Fingerprint/integrity errors need reviewed matching inputs; paths
and locks are never silently rewritten. GObject consumers need their relocated
library/GIR/typelib paths. COM data/QI calls require the constructing thread and
documented apartment; a refcount change does not change that context.

Uninstall by removing the inspected private extraction directory. Its manifest
lists every distribution-owned file. Keep external consumer projects/outputs and
separate package prefixes according to their own ownership. No system registration
or package-manager uninstall step is required.

The development binary archive contains its public libraries, providers and documentation.
Use the matching compiler binary and declared system dependencies with those files. The installed M18 telemetry
example is under `share/astra/examples/optimizer-hardening-18`; its recipe accepts
`--compiler`, `--library-root PREFIX/share/astra` and separate build/runtime output
directories. Select sequential, worker or io_uring composition explicitly; the
last needs an existing matching liburing installation. Generated inputs/outputs
belong in the task's disposable directories.
