# Explicit copied C99 booleans

`bool_abi="c99"` on typed `CImport` or `CExport` functions admits copied Source
`bool` as C99 `_Bool` on GNU x86-64 Linux SysV. The user explicitly approved this
bounded contract in [decision 0141](../decisions/0141-c-union-bool-profile.md).

```astra
[CImport(name="enabled",header="settings.h",bool_abi="c99")]
bool enabled(int id);
[CExport(name="invert",bool_abi="c99")]
bool invert(bool value) { return !value; }
```

The corresponding C signatures are `_Bool enabled(int32_t)` and
`_Bool invert(_Bool)`. The physical channel is LLVM i1 with required `zeroext`
on C return/parameter declarations, exported wrappers and every C call site.
Native bool keeps its existing native ABI. There is no implicit bool/integer
conversion. Selected functions may mix existing copied scalar and opaque pointer
channels. They must contain at least one copied bool parameter/result.

Bool pointers and record storage, GObject `gboolean`, alternate record/text/
buffer/callback/pointer transport groups, owned results, Windows and freestanding
profiles reject. Unannotated legacy `extern(C)`/`export(C)` bool declarations
retain their prior refusals; `CCode` does not silently enable the new contract.
No bool representation, foreign runtime or linker input is added to native-only
programs. C `_Bool` storage assertions in the independent C oracle qualify the
host compiler; they do not grant Source addressable C bool storage.

The admitted policy is copied and checked through checked semantics, Core, CFG,
SSA, native-boundary inventory and C ABI. C ABI distinguishes `CBOOL` from `I32`
and native `B1`, and uses profile `c-bool-v7`. Physical verification requires the
actual zero-extension attributes and selected target requirement. Ordinary LLVM
verification alone can accept a missing ABI attribute, so the mutation proof
removes each declaration/wrapper/call attribute and requires Astra refusal,
restoration and released upstream graphs.

The portable `tests/interop-tooling-14/c-bools.py ASTRAC EXTERNAL_OUTPUT` recipe
compiles strict C11 GCC/Clang producers and clients independently, then executes
Source O0/O1/O2 objects in both directions. It checks canonical false/true, mixed
integer/FP/pointer channels, null pointers, all-stage inspection, unsupported
profiles, preserved legacy refusals and native-only optionality. O0/O2 clients
run under unsuppressed Valgrind. The function policy never authenticates an
arbitrary C provider; that provider must meet the declared C99 contract.
