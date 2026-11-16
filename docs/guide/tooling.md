# Documentation, tooling and migration

Good tooling should make the language contract easier to inspect. `astrac doc`
derives declarations from the existing checked semantic model, including
effective ownership, parameters, generic constraints and source locations. It
does not infer a second language from handwritten signatures. The semantic-only
route must not load LLVM; the current paired-image design and fatal-backend
controls are independently qualified by the API documentation tests.

## Inspect real API documentation

In the pinned environment, choose an explicit external destination:

```sh
"$ASTRA_HOST" doc --output "$ASTRA_BOOK_BUILD/order.json" lib/astra/base/order.astra
python3 -B tools/docs/render.py "$ASTRA_BOOK_BUILD/order.json" --output "$ASTRA_BOOK_BUILD/order.html"
```

Read the resolved contract rather than guessing ownership from surface spelling.
The [library API](../api/library.html) and [compiler API](../api/compiler.html)
are integrated into the offline books. Namespace/enum-variant declaration TypeIds
remain unproven metadata cases; their actual owner/payload contracts are distinct.
The [API authoring guide](../api/authoring.md) explains supported `///` tags,
links and checked examples. Unknown semantics are not repaired by a prettier page.

## Reproduce the book checks

Set `ASTRA_PRODUCTS`, `ASTRA_TOOLCHAIN` and `ASTRA_LINK` to the authenticated
existing product, exact-toolchain and provider manifests. Select fresh absolute
build/runtime leaves beneath the project's external roots:

```sh
python3 -B tools/docs/books.py --check
python3 -B tests/books/run.py --products "$ASTRA_PRODUCTS" --toolchain "$ASTRA_TOOLCHAIN" --link "$ASTRA_LINK" --build "$ASTRA_BOOK_BUILD" --runtime "$ASTRA_BOOK_RUNTIME"
```

The first command performs cheap source/fence/ledger checks. The second is the
actual native campaign; `--quick` is semantic authoring evidence only. To rebuild
compiler products, use the existing [build recipe](../../tools/docs/build.py)
and [paired-image linker](../../tools/docs/link.py) with authenticated producer,
source/tool identities and fresh external leaves. A new checkout also needs its
recorded external LLVM capsule, providers and seed; the books do not bundle or
invent replacements for them.

Render offline books using `tools/docs/books.py --output` with current generated
API JSON inputs. Repeating with `--check` compares exact output bytes and local
links. Complete-book HTML supports browser Find without JavaScript or a server;
the print stylesheet provides page breaks and code wrapping. No PDF is claimed.

## Migrate with evidence

Select modern headers deliberately, review shared-parameter defaults and owning
results, then check source before linking. Use [the feature matrix](../reference/limits.md)
when an old manual disagrees with current native admission. Run the guarded
formatter entry point on task-owned source, preserving protected fixtures.
Retain failed attempts and diagnostics. A version banner, successful build or
formatted code does not waive independent lifetime, ABI or physical verification.
