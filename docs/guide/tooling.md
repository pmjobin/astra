# Documentation, tooling and migration

You have two versions of the readings model and a working application. Now the
useful tooling question is small and concrete: can you inspect the model's
public contract, change its calculation, and check the result without guessing
which sources or compiler were used?

The development tools below work with the authenticated environment established
in Getting started. They do not install Astra or discover packages. The same
explicit inputs that make the application understandable also make its
build and documentation reproducible.

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
ASTRA_CHECK_RUNTIME=$(mktemp -d "$ASTRA_WORK/runtime/guide-check.XXXXXX")
python3 -B tests/books/run.py --products "$ASTRA_PRODUCTS" \
    --toolchain "$ASTRA_TOOLCHAIN" --link "$ASTRA_LINK" \
    --build "$ASTRA_BOOK_BUILD/tooling-check" --runtime "$ASTRA_CHECK_RUNTIME/run" \
    --case guide-app-filter
```

The final line of runner output is `guide-app-filter EXPECTED_OUTCOMES_PASS`.
This selected case checks count 4/total 24, input refusals, both compiler hosts
and both target optimization levels, as well as the existing memory and native
checks. It takes longer than checking syntax. Its logs and result live in the
fresh runtime directory named by `ASTRA_CHECK_RUNTIME`; the sources stay in
the checkout.

When drafting a change, `--quick` on this runner supplies only semantic preflight;
it does not execute a program and cannot replace a native result. You can select
other registered cases with `--case`, using the exact IDs in the
[example manifest](../../tests/books/examples.json). A complete unselected run
is a contributor qualification task, not a prerequisite for every small edit.

## Distinguish a setup failure from a source error

An environment helper refusal happens before your program is compiled. It may
name a missing product or a changed tool identity. Do not repair that by removing
checks or substituting a convenient executable with the same banner.

This controlled exercise alters a copy of the product manifest by adding a
newline. The JSON still parses, but the authenticated file bytes differ:

```sh tutorial=toolchain-mismatch
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

```sh tutorial=environment-repair
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
They are not a bundled installer; improving that initial setup remains separate
work.

## Read and share the local books

The complete Guide and Reference HTML have ordinary links and browser Find.
They need no client-side JavaScript for prose, navigation or searching a complete
book page. The print stylesheet wraps code and separates chapters; this edition
does not supply a designed PDF.

A quick source check verifies the book's fixture fences and links to its source
contracts:

```sh tutorial=book-source-check
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
