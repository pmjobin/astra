# Source files

DIAG-1 [caller information](caller-information.md) reuses these exact lexical
labels and per-file source bytes. Captured strings may embed paths and written
expressions in the executable. Relative-label relocation preserves those bytes;
absolute labels may change. Captures never reopen files or pretty-print Core.

CONST-1 adds native top-level [constants](constants.md) to the whole-program value
namespace. Cross-file forward dependencies are resolved by exact symbol identity,
independent of CLI order. Both boolean operands contribute dependencies; cycles and
invalid unused declarations diagnose with their physical source locations. Constants
collide with native/imported callable names under value lookup, while existing type
and member namespaces remain separate. Files introduce no runtime initialization.

Compile an application from several files in one invocation:

```sh
astrac main.astra types.astra processing.astra -o application
```

Without namespace directives, all files share the existing global native name
rules. File names and directories have no symbolic meaning. Optional explicit
[namespaces and using directives](modules.md) add source organization within the
same explicit source set; they never load files. Prototypes, partial types and
independently compiled Astra interfaces remain unsupported. Functions and types
in the legacy global mode may reference later
declarations or declarations in any other supplied file. Mutual function recursion
works across files. Duplicate declarations reject globally, including two `main`
functions. Existing executable entry requirements and dump modes are unchanged.

`types.astra`:

```astra
struct Lab { f64 l; f64 a; f64 b; }
```

`processing.astra`:

```astra
Lab transform(Lab input) {
	var result = input;
	result.l = result.l * 2.0d;
	return result;
}
```

`main.astra`:

```astra
int main() {
	Lab input = { l = 21.0d, a = 0.0d, b = 0.0d };
	var output = transform(input);
	if (output.l != 42.0d || input.l != 21.0d) { return 1; }
	return 0;
}
```

Class methods/properties, ordinary Resource/Class/slice borrowing, explicit
owned/move boundaries, buffer results and caller-provided ObjectStorage use the
same contracts across files. Structs remain nominal: matching fields do not make
differently declared types interchangeable. Generic definitions are checked once;
identical concrete demands from several callers share one specialization.

Input argument order does not affect legality, selected diagnostics or canonical
dumps. Canonical internal order is lexical normalized source path order within
the compiler's existing declaration categories, followed by byte position. This
is not an execution or initialization order. Renaming a file may change diagnostic
names and compiler ordinals, but cannot create a new language namespace.

Each file starts at line 1. Diagnostic paths normalize redundant separators and
`.` components, so `./foo.astra` and `foo.astra` identify the same input and supplying
both rejects. `a/common.astra` and `b/common.astra` remain distinct. Relative names
stay relative; absolute names stay absolute. Case, `..` and symlinks are not
canonicalized. No directory search, glob expansion or recursive discovery is added.

Use `--parse FILE...`, `--dump-syntax FILE...`, `--check FILE...`, or an existing
semantic/IR/ABI/LLVM dump option with all source paths. Existing `--vapi PATH`
metadata is available globally without changes to its loading order or foreign
contracts. `--link-object` still supplies external objects to the final executable
link; it does not link separately compiled Astra files. One source retains the
existing syntax dump; multiple sources print `(program (source "path" (unit ...)) ...)`.
Paths in that internal format escape quotes, backslashes and control bytes.

The CLI retains the baseline's content-based input behavior: `.astra` is the
ordinary source extension, but the accepted driver did not reject other suffixes.
No new file kind or filename filter is introduced. Zero-source behavior, decoding,
output replacement and the absence of stdin/library modes remain unchanged.

## Inferred generic calls across files

A generic helper in one source can be called as `identity(42)` from another.
An outer generic in a third source can call `identity(value)` with its exact outer
T identity. [GEN-INFER-1](generic-inference.md) resolves the same program-owned
function definition and ordered semantic arguments as explicit calls. Inferred
and explicit requests deduplicate globally after substitution. File paths are
provenance only; all CLI permutations produce identical canonical stages.

## Native text literals

TEXT-1 adds ordinary double-quoted UTF-8 literals with explicit decoded byte payloads
and source byte spans. Embedded escaped zero survives tokens, constants and dumps.
SourceFile still rejects malformed input encoding and raw NUL before lexing; the
file-BOM policy is unchanged. U+FEFF inside a literal is content. The CLI requires
the whole file to be smaller than INT_MAX bytes. [Text grammar](text.md) is independent
of VAPI/CCode metadata strings. Canonical source order also controls deterministic
first-use literal pooling; relocation preserving relative order retains ordinals.
Arbitrary source renaming does not promise ordinal stability.
