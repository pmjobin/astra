# Native text-v9

text-v9 is the next profile after accepted buffer-v8; v0..v8 are not renumbered.
Only signatures with string parameters/results select text-v9. In a module with
text, other signatures retain the profile they would select without text.
Body-only text does not change an otherwise scalar signature or CABI profile.

| Logical boundary | Independent physical plan | Contract |
| --- | --- | --- |
| string parameter | NativeTextType(base PTR, byte_length I32), two ordered channels | BORROWED_NOESCAPE |
| string result | NativeTextType(base PTR, byte_length I32), backend {ptr,i32} result carrier | STATIC_TEXT |

NativeTextType owns scalar enums and its explicit text role/contract. It retains
no frontend, semantic, CFG/SSA or CABI objects. Independent verification checks
component type/order, supported profile and parameter/result role. Signature
correspondence checking additionally enforces exact canonical StringType, arity,
source grouping, receiver placement and all mixed aggregate/buffer boundaries.
A physical PTR/I32 resemblance does not make text a mutable slice or owned buffer.

Parameters may alias. Length is nonnegative; nonempty bases point to readable
well-formed UTF-8 bytes stable for the borrow. Zero length permits null and does
not require readable storage. No sentinel, exclusivity, nonnull, noalias,
cleanup token or reference count is promised. Literal construction validates
bytes; arbitrary incoming memory is a native producer precondition, not something
an independent compiler verifier can inspect. Test-only LLVM wrappers honor it
with separately allocated exact-length data, including guarded page boundaries.
Those wrappers are not public Astra CABI support.

Results promise backing valid throughout the generated program. They can forward
static results or select static literals/constants through locals and control
flow. Incoming text never becomes static merely because current callers pass
literals. Future owned or lifetime-parameterized returns require new explicit
contracts. There is no hidden result-storage parameter for string results.

LLVM internal fastcc, existing receiver rules, scalar/vector/struct channels,
borrowed slices, owned buffer pairs, Resource transfers and owned object storage
continue to compose. Constructor text parameters use ordinary constructor syntax.
Text fields/properties/collections remain excluded despite physical capability.

Nonempty literals use private constant exact-size byte arrays; empty text is
{null,0}. Ordinals belong to a separate module-local first-use pool keyed by full
length and bytes, never source names or host addresses. A generated internal
bounded equality helper needs no external text runtime. Byte length excludes any
implementation storage outside the view; TEXT-1 emits no trailing sentinel.

LLVM 22 global constant rules are described in the qualified
[LangRef](https://releases.llvm.org/22.1.0/docs/LangRef.html#global-variables).
The helper's local `no-builtins` policy uses LLVM TargetLibraryInfo; see
[its implementation](https://www.llvm.org/doxygen/TargetLibraryInfo_8h_source.html).
O0/O2/+FMA object symbol audits and exact-length runtime probes qualify the local
Linux x86_64 target, not untested target execution.

CABI is unchanged. Source extern(C), export(C), and VAPI string signatures reject.
Independent metadata strings keep their prior escape/NUL/name/header rules.
No char*, C aggregate, c_str, printing, process arguments or external byte-decoding
policy is selected. See [text language rules](../language/text.md) and
qualification.
