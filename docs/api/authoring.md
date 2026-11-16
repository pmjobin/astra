# API documentation author guide

Write a contiguous run of `///` lines immediately before its declaration.
One optional space after each marker is stripped; other Markdown bytes are
preserved. A blank line, ordinary comment, brace or ineligible declaration is
an association barrier and produces an unattached-comment diagnostic. Indentation
does not select an owner. Ordinary `//`, block comments and `////` remain ordinary
trivia. There is no `//!` module-doc extension in this version. All source inputs
retain their normal language profile and UTF-8 validation.

Document actual contracts. The generator derives types, effective qualifier
flags, shared/weak policy and errors from checked tables. A sentence cannot
change those facts. Checked semantics do not establish native lowering, whole
program ownership flow or a new safety guarantee for an unsupported policy.

For a documented callable, use `@param name Description` for each parameter and
`@return Description` for a nonvoid result. Duplicate or unknown parameter names,
missing result documentation and result tags on void declarations are errors.
`@throws CanonicalError Description` must match the resolved error contract.
`{@link CanonicalName}` resolves an exact visible Binder declaration; invisible,
ambiguous and missing targets are errors. JSON retains the Markdown and checked
target IDs. HTML escapes raw markup and external URLs; it supports paragraphs,
`#` headings, fenced code and checked symbol links. It is a bounded Markdown
subset, without embedded HTML, remote images, MDX or script execution.

An explicit example fence has this grammar:

````markdown
```astra name=answer mode=run category=freestanding exit=42
int main() { return 42; }
```
````

Names match `[a-z][a-z0-9-]{0,63}` and are unique in the document. Modes are
`compile`, `run`, and `compile_fail`. Every example is a complete compilation
unit, including a `main` when required by the current compiler. Categories are
`freestanding` and `hosted`; hosted examples require an explicitly authenticated
provider-object manifest. `exit` and optional `stdout` assert run behavior.
`diagnostic` is required for compile-fail and must match the intended compiler
diagnostic. Optional `library` selects one repository-relative `.astra` source.
Metadata uses shell-style quoting only as text parsing; no shell executes it.

Run examples separately with `python3 -B tools/docs/examples.py`, passing the
generated JSON, exact native compiler path/hash, isolated `--build`/`--runtime`
and optional `--link` provider manifest. The runner compiles O0 and O2, checks
expected outcomes and preserves compile-failure destination sentinels. Rendering
never performs this action. At most 128 examples and 256 links per declaration
are accepted; comment bodies are bounded at 65,536 bytes.

Use `--toolchain` with the authenticated LLVM 23.1.4 build-identity receipt when
the host LLVM differs. `--strict-memory` additionally checks every example's
compiler invocation and executed program with unsuppressed all-kinds Valgrind.
An example fixture used to test this runner is separate evidence from examples
extracted by the native compiler.
