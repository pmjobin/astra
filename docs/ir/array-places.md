# Array storage and indexed Places

[Record collection entries](struct-elements.md) extend ArrayInitialize with exact indexed storage targets and complete named-field/producer initialization. Arrays become available only after every entry. Ordinary scalar/vector entry representations and dumps remain unchanged.

[Slice construction](slice-values.md) borrows this exact storage without loading
a whole ArrayType value. ArrayElementPlace remains distinct from
[SliceElementPlace](slice-places.md): the former has fixed local extent, the latter
captures one runtime view. `len(array)` lowers to an int constant; explicit
`slice(array,start,count)` retains separate checked range authority. No decay or
element address-of is exposed, and array/slice writes share the same storage.

The shared immutable ArrayType contains exact element identity and length,
without syntax, symbols, stage objects, layout, ABI or LLVM backlinks.
BuiltinTypes canonicalizes the pair. Stage verifiers independently reject
unsupported element categories, lengths outside 1..1024, and inconsistent
canonical identities. Arrays are accepted only as local storage types; existing
value/signature verifiers continue to reject them.

| Stage | Storage | Initialization | Access |
| --- | --- | --- | --- |
| Checked | LocalSymbol with ArrayType | CheckedArrayLocalDeclaration, N expressions or typed record entries | CheckedArrayElementPlace |
| Core | non-promotable CoreLocalPlace | CoreArrayInitialize, ordered Values or complete record producers/initializers | CoreArrayElementPlace |
| CFG | non-promotable CfgLocalPlace | ordered captures, CfgArrayInitialize; one complete action per record entry | CfgArrayElementPlace and CfgArrayBoundsCheck |
| SSA | SsaAddressableLocal | SsaArrayInitialize, captured scalar/vector Values or complete entry leaves | SsaArrayElementPlace and SsaArrayBoundsCheck |
| LLVM | `alloca [N x T]` | ascending elements; recursive leaf stores for records | validated plain GEP and exact load/store |

Each element Place retains exact storage, exact ArrayType, index Value, exact
element type, and immutable LOCAL provenance with local/region ordinals. Core
uses the checked index tree. CFG evaluates it once at the source access point.
Dynamic bounds checks produce a validated integer result; that result, not an
unchecked index expression, is retained by the Place. The verifier associates
the result with its exact storage and checks definition order/dominance.
Constants are accepted only when their mathematical values are in range.

For assignment, CFG emits index evaluation and validation before lowering the
RHS. SSA retains that ordering in its instruction list, including when the RHS
introduces calls, traps or expression regions. A Load/Store alone cannot supply
validated-index authority. There are no array pointer arithmetic operations.

Core verifies exactly N exact-typed initializers before making storage
available. CFG captures each expression before starting the next; its dedicated
initialization verifies completeness and must dominate accesses. SSA verifies
one initialization site per live storage object, complete typing/count and
initialization dominance. Unreachable declarations may retain unused storage
without executed initialization, as in the existing addressable-local model.
No storage use can precede complete initialization. For scalar/vector arrays the
backend stores captured element values after every initializer has finished;
the unavailable local and prohibition on address escape preserve the existing
contract. Record entries instead finish their complete captures and stores before
the next entry begins. Their final entry establishes array initialization dominance.

There is no CoreArrayValue, whole-array SSA result, or decomposition into N
synthetic Astra locals. Scalar access produces one scalar result. Vector access
produces one whole-vector Load result or consumes one whole-vector Store value.
`blocks[i][k]` is an indexed array Place, Load of its vector type, then
VectorExtractValue/Instruction. Neither that extraction nor insert creates a
LanePlace. Numeric element values reuse existing arithmetic authorities.

At LLVM, bounds compare using the original exact IntegerType. Signed negatives
trap; a representable upper bound uses signed/unsigned comparison. When N exceeds
the index type's positive maximum, the upper-bound failure is impossible and
that comparison is omitted. Only afterward does zero-extension to i64 normalize
a nonnegative ordinal for a two-index plain GEP. It is physical normalization,
not an ICONV-1 `as`. Initializer indices are direct valid constants.

The array type mapper is storage-only and never adds a NABI/CABI channel.
Array/vector object alignment comes from the backend target data layout.
Guard continuations update LlvmBlockState.end, the established authority for
actual physical predecessors. Invalid paths call llvm.trap and terminate before
GEP/load/store. ARRAY-1 uses no inbounds GEP, runtime helper, heap allocation,
production dependency, byte-stride exposure, or foreign array representation.

See [ADR 0045](../decisions/0045-fixed-local-arrays.md),
[language rules](../language/arrays.md), and validation.
