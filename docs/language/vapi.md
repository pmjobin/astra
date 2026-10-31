# External C declarations with VAPI

The selected [GIR importer](gobject-interop.md) can generate typed VAPI plus
native consuming helpers and independently checked C bridges. Plain `--vapi`
does not itself parse GIR or authenticate a generated contract manifest.

RESOURCE-1 adds [handle declarations](../vapi/handle-types.md) to VAPI's declaration
kinds. All handle names join the ordinary type namespace before signatures are
resolved, including across CLI files. A required nonempty destroy_function on the
type supplies owned-result cleanup; optional headers remain opaque and cname is
invalid on types. Functions use `owned Resource`, `borrowed Resource`, or unmanaged
Resource. Native owned boundaries and C-exported handles remain deferred.

A VAPI file supplies typed C function imports outside an Astra source file.
The file implies the C import domain:

```text
// helper.vapi
int astra_test_add(int a, int b);
void astra_test_reset();
```

```astra
// program.astra
int main() {
	astra_test_reset();
	if (astra_test_add(20, 22) != 42) {
		return 1;
	}
	return 0;
}
```

```sh
astrac --vapi helper.vapi --check program.astra
astrac program.astra --vapi helper.vapi --dump-cabi
astrac --vapi helper.vapi program.astra --link-object helper.o -o program
```

`--vapi PATH` is repeatable and may precede or follow the Astra source. It works
with `--check`, `--dump-semantics`, `--dump-core`, `--dump-cfg`, `--dump-ssa`,
`--dump-nabi`, `--dump-cabi`, `--dump-llvm`, and executable compilation. Syntax-only
`--parse` and `--dump-syntax` retain their single Astra source argument and reject
`--vapi`. The Astra syntax dump never contains injected VAPI declarations.
`-o` and `--link-object` remain executable-only options.

A declaration such as `int astra_test_add(int a, int b);` is semantically the
same C import as `extern(C) int astra_test_add(int a, int b);` in Astra source.
Both use CFunctionSymbol and the existing foreign-call pipeline. Source externs
remain fully supported, but declaring the same function by both paths is an
error. Without metadata the VAPI name is also the exact C external symbol name.

The [complete grammar and lexical contract](../vapi/vapi-scalar-v0.md) permits
handle declarations and function declarations: functions have a return type name, function name, parentheses,
comma-separated named parameters, and a semicolon. Parameters may be int, float/f32, double/f64, void* or imported handles;
results may also be void. Both `//` and non-nesting `/* ... */` comments work.
Files must be valid UTF-8; identifiers use ASCII letters, underscores, and digits
with no leading digit. Parameter names are mandatory and unique. Foreign bool
is unsupported. Bodies, explicit extern(C), and exports reject.

An optional `[CCode (...)]` immediately before a declaration supports two
case-sensitive keys:

```text
[CCode (cname = "astra_test_add_impl", cheader_filename = "helper.h")]
int add(int a, int b);
```

Astra calls `add(20, 22)`. The physical CABI/LLVM symbol is `astra_test_add_impl`;
that spelling does not create another Astra callable. `cheader_filename` retains
one nonempty, NUL-free opaque header name. It may be nonexistent: Astra never
opens or parses it, and it does not link libraries or objects. `cname` is also
nonempty and NUL-free, without an Astra identifier restriction. Either key may
be omitted; unknown attributes/keys and duplicate keys reject. Strings permit
UTF-8 and `\"`, `\\`, `\n`, `\r`, `\t` escapes. Empty CCode attributes, trailing
commas, and raw multiline strings are unsupported. See [metadata v0](../vapi/vapi-c-metadata-v0.md).

Multiple files contribute one direct-function namespace:

```sh
astrac --vapi arithmetic.vapi --vapi state.vapi program.astra \
	--link-object arithmetic.o --link-object state.o -o program
```

All inputs are collected before native bodies are checked, so forward calls
work regardless of source order or CLI position. Imports appear in dumps with
source externs first, then VAPI files in CLI order and declarations in file order.
Export ordering is unchanged. Repeated names are errors across files, within a
file, and against source externs/native definitions/exported definitions. Passing
the same path twice also produces duplicate declarations. The error points to
the later declaration in merge order, with its VAPI filename, line, and column.
Different local names with the same physical symbol instead fail at CABI,
including aliases colliding with source externs or exports. Aliases never change
import ordering or Astra left-to-right/effect semantics. Header metadata changes
only metadata dumps; CABI signatures and LLVM IR stay identical. NABI is unchanged.

VAPI supplies declarations only. It does not supply code, parse headers, invoke
a C compiler, or choose libraries. `--link-object helper.o` supplies the existing
implementation independently. Checking, CABI dumping, and LLVM dumping succeed
without that object; linking a used unresolved symbol fails while preserving any
previous executable output and cleaning compiler temporaries.

`.vapi` is the conventional suffix. Explicit paths with another suffix, spaces,
or punctuation work; paths are read directly. For a path beginning with `-`, use
`./` to distinguish it from an option.

Source extern/export aliases, header parsing/includes, link metadata, typed pointers,
richer C types, foreign bool, callbacks, variadics, ownership transfer/nullability,
array metadata, namespaces/modules, GIR, and GObject remain unsupported.
VAPI has no exports; use source
[`export(C)` definitions](c-exports.md). Future VAPI features must enrich the
existing foreign model. See [ADR 0022](../decisions/0022-vapi-foreign-declarations.md)
and [ADR 0023](../decisions/0023-vapi-c-metadata.md).

## Pointer declarations

```text
[CCode (cname = "astra_test_handle_a", cheader_filename = "nonexistent/pointer_api.h")]
void* handle_a();
int is_null(void* p);
```

The independent VAPI grammar adds one optional star after a type identifier;
whitespace/comments do not affect spelling. Extra stars are retained for a
semantic diagnostic. Only void* is supported; int*, bool*, and void** reject with
VAPI filename/line/column. VAPI adds no null-expression grammar. Normalization
copies canonical type spelling and source provenance into generic foreign inputs,
then the ordinary C symbol and IR path apply. CCode syntax and header policy are
unchanged. See [C pointer ABI](../abi/c-pointer-v1.md).

## Owned-result metadata

CCode also accepts `destroy_function = "exact_external_symbol"` on void* results.
It normalizes to an immutable generic cleanup contract and requires a direct
`owned void*` local initializer in source. Destroyers need no source declaration;
headers remain opaque. Empty symbols, duplicate keys, unsupported results, and
ordinary raw consumption reject. See [owned results](../vapi/owned-results.md).

## Borrowed parameters

VAPI accepts `int inspect(borrowed void* p);` with the same normalized contract as
source extern(C). `borrowed` is parameter-only and requires void* or an exact imported handle. It promises
noescape, non-owning access, while allowing mutation and I/O. Owners must be
OWNED and retain their state and cleanup after the call; raw pointers and null
are compatible. Native wrappers enforce direct noescape forwarding. Foreign
implementations are trusted. See [binding rules](../vapi/borrowed-parameters.md).


## C float and double

```text
[CCode (cname = "c_echo_float")]
float echo_float(float value);
[CCode (cname = "c_echo_double")]
double echo_double(double value);
```

These declarations bind ordinary Astra f32→f32 and f64→f64 functions in the
foreign C domain. Normalization maps the exact scalar spellings float→f32 and
double→f64, retaining the original VAPI spans. The ordinary CFunctionSymbol
holds that semantic type and ForeignAbi.C; this unambiguously selects the
C-float/C-double mapping at CABI planning. Original f32/f64 VAPI spellings also
work. No VAPI-specific later representation or source-level float/double alias
exists. VAPI objects can be destroyed before Core and later stages run.

The [scalar-fp-v2 contract](../abi/c-fp-v2.md) qualifies target representation,
exact transport and mixed signatures. No implicit width or integer promotion
is introduced. Only scalar spellings normalize: float*/double* remain rejected,
as do C aggregates, varargs and callbacks. Process arguments are unrelated and
remain excluded.
