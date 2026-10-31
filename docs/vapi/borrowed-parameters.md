# VAPI borrowed parameters

RESOURCE-1 extends borrowed parameters to imported nominal handles. For
`int inspect(borrowed Resource r);`, the argument must be exact Resource or
contextual null. Owner adaptation preserves OWNED and native borrowed forwarding
enforces noescape; cross-handle and Handle/void* arguments reject before CABI.
The physical channel remains PTR, with BORROWED_NOESCAPE supplemental behavior.
See [handle types](handle-types.md).

VAPI declares trusted foreign noescape contracts with a parameter qualifier:

```text
[CCode(cname = "resource_create", destroy_function = "resource_destroy")]
void* create_resource(int id);

[CCode(cname = "resource_is_live", cheader_filename = "resource.h")]
int is_live(borrowed void* resource);
```

```astra
owned void* h = create_resource(1);
int live = is_live(h);
```

The call leaves `h` OWNED and its existing lexical cleanup intact. Passing raw
unmanaged `void*` or `null` is also valid. An owned-producing expression must
first initialize an owner. Borrowing requires definitely OWNED state, including
for an owner whose actual pointer is null; MOVED and MAYBE_OWNED reject.

The independent VAPI grammar is `parameter := "borrowed"? type-name identifier`.
`borrowed void*` and exact `borrowed Handle` parameters are semantically valid. Other types, borrowed results,
borrowed storage, and exported borrowed APIs are outside this milestone.
`borrowed` is a keyword, separate from CCode metadata. It coexists with `cname`,
`cheader_filename`, and owned-result `destroy_function` declarations; headers
remain descriptive and are not opened or analyzed.

The binding author promises synchronous non-owning use: no retaining, freeing,
destroying, storing, returning, transferring, or later exposure of the borrowed
address. Resource mutation and I/O are allowed. Borrowed does not imply readonly,
purity, or permission to reorder/discard calls. A violating C implementation
breaches the foreign-interface contract. Astra performs no C analysis.

VapiParameterSyntax retains the keyword and source span. Normalization produces
ForeignParameterInput with ordinary `void*` type spelling and
`PointerParameterContract.BORROWED_NOESCAPE`. Semantic collection creates the same
ParameterSymbol and CFunctionSymbol used by source
`extern(C) int is_live(borrowed void* resource);`. All downstream stages preserve
the same contract apart from source provenance; no VAPI-specific IR parameter
class exists. Native wrappers can forward directly to these C parameters.

CABI adds behavioral metadata only:

```text
(parameter #0 PTR (contract borrowed-noescape))
```

The profile remains `scalar-ptr-v1`; LLVM declares an ordinary `ptr` parameter
and uses C convention. No borrow runtime node or LLVM optimization attribute is
required. Compiler-owned cleanup functions remain a distinct destructive
contract, and their PTR parameter is not reinterpreted as borrowed.
See [language rules](../language/borrowed-parameters.md),
[owned results](owned-results.md), and [ADR 0030](../decisions/0030-borrowed-owner-parameters.md).
