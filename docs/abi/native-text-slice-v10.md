# Native text-slice-v10

The registry's successor to `text-v9` is `text-slice-v10`. This internal capability
profile adds borrowed read-only text-descriptor tables. It does not change public
CABI text-view-v3 or promise cross-version binary compatibility.

| Group | Ordered components | Contract |
| --- | --- | --- |
| Outer slice parameter | table PTR, count signed I32 | one deep borrowed/noescape view |
| Table element in memory | data PTR, byte_length signed I32 | immutable validated UTF-8 view; read-only slot |

`NativeTextSliceType` extends physical slice grouping and owns a
`NativeTextDescriptor` with explicit roles, ordinals, natural-layout requirement
and borrowed text contract. These are independent ABI plans, not a second source
string or argument type. Shape/access/deep-borrow verification is independent of
source correspondence. A valid ordinary numeric slice plan cannot substitute
for a text slice merely because its outer channels are PTR/I32.

On qualified x86-64 Linux LP64, descriptor offsets are 0 and 8, stride is 16 and
alignment is 8. The length occupies four bytes; remaining bytes are padding.
The record is not packed. LLVM 22 `LLVMOffsetOfElement`, `LLVMABISizeOfType`,
`LLVMABIAlignmentOfType` and `LLVMPointerSize` produce the selected target's
layout witness, which must match provider assertions before emission. No source
64-bit integer, per-element heap box, argc-sized signature or hidden result
parameter is introduced.

LLVM expands each outer parameter to two fastcc channels, alongside existing
receiver, scalar, vector, aggregate and owned-buffer channels. The body keeps
complete grouped views and complete loaded text pairs. Only a signature with a
text-slice parameter selects v10; an unrelated scalar signature does not acquire
v10 from its body or another function. Existing text-only signatures stay v9 and
text-free profiles retain their accepted behavior.

Other targets fail the explicit text-slice object capability gate. Existing
qualified numeric/native-text programs retain their gates. Target qualification
does not define an x86-specific source language. [LLVM 22 layout rules](https://releases.llvm.org/22.1.0/docs/LangRef.html#data-layout)
and [structure types](https://releases.llvm.org/22.1.0/docs/LangRef.html#structure-types)
describe the backend representation authority.
