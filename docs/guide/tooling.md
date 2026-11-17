# Documentation, tooling and migration

You have two versions of the readings model and a working application. Now the
useful tooling question is small and concrete: can you inspect the model's
public contract, change its calculation, and check the result without guessing
which sources or compiler were used?

The commands below use the installed tutorial workspace from Getting started.
API extraction runs without loading LLVM. The installed Python renderer converts
its versioned JSON to local HTML; it needs no network service.

## Inspect the model you just used

`astrac doc` derives declarations from the checked semantic model. Ask it to
extract the original readings model, then render that JSON as a local page:

```sh tutorial=model-docs
"$ASTRA_HOST" doc --output "$ASTRA_BOOK_BUILD/model-api.json" tests/books/app-model.astra
python3 -B tools/docs/render.py "$ASTRA_BOOK_BUILD/model-api.json" \
    --output "$ASTRA_BOOK_BUILD/model-api.html"
```

Open `model-api.html` in a browser. Find `Readings.Summary` and `summarize`:
the record has count and total fields, and the function's input is borrowed.
The page describes declarations and effective ownership, not whether the
algorithm's arithmetic is correct. Running the application supplied that
separate observation.

The integrated [library API](../api/library.html) and
[compiler API](../api/compiler.html) use the same declaration-based format.
The [authoring guide](../api/authoring.md) explains documentation comments,
links and checked examples. API extraction follows a semantic-only path; it
does not compile, link or execute your application.

## One edit, one focused check

Exercise: extract the API for the complete calibration-filter answer and check
its running result. Predict what should change: the computation excludes six,
but the model still offers a `Summary` and a borrowing `summarize` function.
The complete source is [guide-app-filter.astra](../../tests/books/guide-app-filter.astra),
so you can compare a working answer with your own edit.

```sh tutorial=tooling-answer
"$ASTRA_HOST" doc --output "$ASTRA_BOOK_BUILD/filtered-api.json" tests/books/guide-app-filter.astra
python3 -B tools/docs/render.py "$ASTRA_BOOK_BUILD/filtered-api.json" \
    --output "$ASTRA_BOOK_BUILD/filtered-api.html"
"$ASTRA_HOST" -c -O2 -o "$ASTRA_BOOK_BUILD/tooling-check.o" \
    tests/books/guide-app-filter.astra tests/books/app-main.astra
cc -no-pie "$ASTRA_BOOK_BUILD/tooling-check.o" "$ASTRA_BOOK_BUILD/readings-provider.o" \
    -o "$ASTRA_BOOK_BUILD/tooling-check"
ASTRA_STATUS=0
ASTRA_READINGS_INPUT="$PWD/tests/books/readings.txt" "$ASTRA_BOOK_BUILD/tooling-check" \
    || ASTRA_STATUS=$?
test "$ASTRA_STATUS" -eq 42
```

The report is `readings: count=4 total=24` with a final newline and exit 42,
the application's documented test sentinel. The API contract still describes
the same record and borrowing function; execution checks the changed calculation.

## Find the matching books and remove the package

Open `/usr/share/astra/books/index.html` for the installed Guide, Reference and
library/compiler API. These pages and their source downloads are generated from
the package's source revision. `/usr/share/astra/PROVENANCE.json` identifies that
revision and the compiler/bootstrap inputs. The Reference's formal 28-A2-R1
coverage remains PARTIAL with 222 unclosed witnesses; packaging does not close
that ledger.

The package includes all 63 Book fixtures as source. It installs no prebuilt
lesson object files. System `cc` builds C providers in your lesson workspace.
The complete Guide and Reference support browser Find and print styles; a
designed PDF is not supplied.

To reinstall the same verified package, use `sudo apt-get install --reinstall`
with its DEB filename, or `sudo dnf reinstall` with its RPM filename. To remove
Astra, use the matching command:

```console uninstall=deb
sudo apt-get remove astra-development
```

```console uninstall=rpm
sudo dnf --setopt=clean_requirements_on_remove=False remove astra-development
```

Removal deletes the compiler and its private files. Your own workspace and the
system C compiler/Python remain. Cross-version upgrades have not been qualified.

## Contributor appendix

The following retained recipes describe the authenticated 28-A2 development
workspace and its historical manifests. They are for compiler contributors;
the installed lessons above do not need this workspace. Their original
qualification remains tied to the earlier report, not to an installed 28-C1
compiler. Current package generation and CI recipes are described in
[the engineering instructions](../../tools/ci/README.md).

### Historical development environment

This edition runs on GNU/Linux x86-64 with LLVM **23.1.4**, an authenticated
Astra compiler, Python 3.11 or later for the setup helper, and a host C linker
(`cc`). A fresh Git working tree also needs
the project's qualified external compiler products and their manifests. Cloning
the sources alone does not create them. There is no installer supplied by this
chapter; [Tooling](tooling.md) identifies the existing build and linking recipes
if you need to reproduce the development environment.

The following commands use the established workspace layout. Run them in a
terminal and keep that terminal open for the next chapters. This recipe assumes
the checkout and external products are already at the paths shown below; a
relocated environment needs its own qualified paths and build recipe.

Use a dedicated POSIX-compatible shell for these lessons. The first line enables
`set -eu`, so an unhandled failed command or unset variable stops the recipe.
The deliberate failure examples capture their statuses explicitly. If a real
setup or build failure ends the shell, correct it and start a fresh lesson session.

```console contributor=setup
set -eu
cd "$HOME/Workspace/astra"
export ASTRA_WORK="$HOME/Workspace/codex/work/astra"
export ASTRA_PRODUCTS="$ASTRA_WORK/runtime/api-docs28a1-products.json"
export ASTRA_TOOLCHAIN="$ASTRA_WORK/runtime/selfhost27c-dev21/build-identity.json"
ASTRA_BOOK_BUILD=$(mktemp -d "$ASTRA_WORK/build/guide-pilot.XXXXXX")
export ASTRA_BOOK_BUILD
python3 -B tests/books/environment.py \
    --products "$ASTRA_PRODUCTS" --toolchain "$ASTRA_TOOLCHAIN" \
    --output "$ASTRA_BOOK_BUILD/environment.sh" &&
    . "$ASTRA_BOOK_BUILD/environment.sh"
```

The [setup helper](../../tests/books/environment.py) checks the selected manifest,
compiler and tool bytes, then writes a small shell environment file in the new
build directory. The final line loads it and sets `ASTRA_HOST` to the selected
compiler. It neither installs a compiler nor chooses an unverified substitute.
If it reports an unavailable environment, stop here and resolve the named
missing file or identity mismatch. That is a setup problem, not an error in
our six-line Astra program.

`ASTRA_BOOK_BUILD` is an unused directory outside the source tree. Each invocation
of the setup commands creates another one, so earlier work is preserved.

### Distinguish a contributor setup failure from a source error

An environment helper refusal happens before your program is compiled. It may
name a missing product or a changed tool identity. Do not repair that by removing
checks or substituting a convenient executable with the same banner.

This controlled exercise alters a copy of the product manifest by adding a
newline. The JSON still parses, but the authenticated file bytes differ:

```console contributor=toolchain-mismatch
python3 - "$ASTRA_PRODUCTS" "$ASTRA_BOOK_BUILD/changed-products.json" <<'COPY'
from pathlib import Path
import sys
Path(sys.argv[2]).write_bytes(Path(sys.argv[1]).read_bytes() + b'\n')
COPY
ASTRA_STATUS=0
python3 -B tests/books/environment.py \
    --products "$ASTRA_BOOK_BUILD/changed-products.json" --toolchain "$ASTRA_TOOLCHAIN" \
    --output "$ASTRA_BOOK_BUILD/untrusted-environment.sh" \
    2> "$ASTRA_BOOK_BUILD/environment-error.txt" || ASTRA_STATUS=$?
test "$ASTRA_STATUS" -eq 1
test ! -e "$ASTRA_BOOK_BUILD/untrusted-environment.sh"
python3 - "$ASTRA_BOOK_BUILD/environment-error.txt" <<'CHECK'
from pathlib import Path
import sys
assert 'products manifest differs' in Path(sys.argv[1]).read_text()
CHECK
printf '%s\n' 'Changed environment input refused before compilation.'
```

The diagnostic in `environment-error.txt` names the manifest mismatch. The
complete repair is to select the original authenticated input again, with a
new output filename:

```console contributor=environment-repair
python3 -B tests/books/environment.py \
    --products "$ASTRA_PRODUCTS" --toolchain "$ASTRA_TOOLCHAIN" --link "$ASTRA_LINK" \
    --output "$ASTRA_BOOK_BUILD/rechecked-environment.sh"
. "$ASTRA_BOOK_BUILD/rechecked-environment.sh"
```

This is deliberately more exact than a version check. A new checkout still
needs the existing authenticated compiler products, seed, LLVM capsule and
providers. The repository's [build recipe](../../tools/docs/build.py) and
[paired-image linker](../../tools/docs/link.py) are contributor tools for
reproducing those products with explicit identities and external outputs.
The 28-C1 package route uses the current explicit bootstrap, distribution and
clean-install receipts; these older manifests remain historical inputs.

### Rebuild and check the local books

The complete Guide and Reference HTML have ordinary links and browser Find.
They need no client-side JavaScript for prose, navigation or searching a complete
book page. The print stylesheet wraps code and separates chapters; this edition
does not supply a designed PDF.

A quick source check verifies the book's fixture fences and links to its source
contracts:

```console contributor=book-source-check
python3 -B tools/docs/books.py --check
```

Its success is a source/preflight result, not evidence that every example ran.
For contributors rebuilding the complete local site, the renderer takes explicit
library/compiler API JSON inputs and an external output directory. The
[renderer source](../../tools/docs/books.py) and campaign recipes preserve those
inputs; generated HTML does not belong in the source tree.

When moving an older source to this edition, select the per-file language profile
deliberately and review the effective ownership contracts. A namespace does not
upgrade imported files. If an old manual's construct is refused, consult the
[current limits](../reference/limits.md) before assuming a spelling correction
will make it native. Next, [Profiles](profiles.md) separates this source-language
choice from the runtime and link choices of the final executable.
