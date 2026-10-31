# Whole native struct copy

[Struct collection elements](struct-elements.md) participate as exact indexed source/destination Places. Destination bounds validation precedes RHS effects, all source leaves are captured before copy-generated writes, and completed element snapshots can outlive their array. Borrowed views may alias; live indexed destinations and receivers still protect their backing owners.

An initialized native struct can initialize another local or replace existing
storage of the exact same nominal type:

```astra
struct Pair { int first; f64 second; }
int main() {
	Pair a = { first = 42, second = 3.5 };
	Pair b = a;
	b = a;
	b.first = 7;
	if (a.first != 42 || b.first != 7) { return 1; }
	return 0;
}
```

The existing declaration and assignment grammar supplies both forms. No new
keyword is needed. `a` remains initialized and usable. Subsequent mutations to
`b` do not mutate `a`; copying a void* field preserves the pointer identity,
not a clone of its pointee. Copy transfers no ownership and `move a` is unsupported.

The operation is Place→Place. Sources can be locals, recursively nested fields,
dereferenced concrete struct pointers, or eligible indexed elements; destinations
can be the same mutable storage forms. For example, `Inner x = outer.inner;`, `outer.left = outer.right;`,
`outer.inner = x;`, `S b = *p;`, `*p = b;` and `*p = *q;` are copy contexts.
Existing restrictions on Place roots, member receivers, subobject address-of and
pointer lifetimes still apply. Methods and property accessor bodies may perform
these copies wherever their existing field/local Places are available.

Copy initialization requires fresh storage: an ordinary local or a complete
entry of an eligible fixed local array. The source is checked before the local
or containing array becomes visible. Copy assignment requires already initialized storage.
Partial initialization remains unsupported. Named brace entries for embedded
structs accept complete nested braces or exact bounded producers under
[GEN-COPY-1](generic-copyable-values.md). Each producer is fully captured before
that field's writes and the next written entry.

Both types must be the **exact same nominal type**. Structs A and B with identical
fields are incompatible. Concrete `Box<int>` and `Box<i32>` interoperate because
int/i32 canonicalize to one identity. `Box<i8>`/`Box<u8>`, distinct definitions
`A<int>`/`B<int>`, and phantom `Tagged<i8>`/`Tagged<u8>` remain incompatible even
when storage layouts happen to match.

The compiler's one recursive Copyability authority accepts these leaves:

| Category | Copyable leaves |
| --- | --- |
| Boolean | bool |
| Integers | i8, u8, i16, u16, int/i32, u32 |
| Floating | f32, f64 |
| Opaque pointer | void* |
| Vectors | All 24 accepted numeric/mask VectorType shapes |
| Nested storage | StructType iff every field is recursively copyable |

Concrete generic instances obey exactly the same rule: `Box<int>`, `Box<f64>`,
`Box<i16<8>>` and nested `Bundle<f64>` copy normally. Generic origin has no bearing
on copyability. Handles/resources, ClassType, arrays, slices and lifecycle-bearing
contracts are outside this authority. Typed-pointer fields remain illegal.
By-value recursive struct cycles are illegal.

Copy evaluates and validates the destination first, then the source, reads all
source leaves in recursive declaration order, and only then writes all destination
leaves in that order. Self-copy and same-storage aliases are valid. A null source
traps before any destination write; a null destination traps before source
copy evaluation. Traps do not unwind. Each vector is one whole leaf, with no lane
storage. Floating copies preserve bits, including signed zero, subnormals,
infinities and accepted quiet NaN payload transport; no arithmetic is performed.

Copy does not force an address or allocation. Unaddressed roots remain eligible
for scalarization, including across branches and loops. Only roots whose address
is otherwise needed become memory-backed. There is no aggregate temporary,
frontend memcpy/memmove, heap, copy helper or runtime descriptor.

A struct Place is not a general expression Value. [STRUCT-ABI-1](struct-values.md)
adds exact native argument/return snapshots and bounded call-result producers for
initialization, assignment, argument and return forwarding. Comparisons and
struct-valued properties remain excluded. There is no aggregate SSA Value or
opaque STRUCT channel. Native aggregate-v7 transports leaves; C aggregate ABI
remains excluded. Existing `S*` parameters still use PTR. Copying/passing/returning
preserves field values, without promising preservation of physical padding bits.

GEN-COPY-1 extends GEN1_PLAIN_COPY through this same recursive authority:
`identity<Box<int>>(box)` and eligible ordinary record arguments are legal.
Parameterized Box<T> copies use exact scoped premises and specialize before CFG.
No source Copy/Move capability exists; Ownable remains ownership-specific.

See [ADR 0061](../decisions/0061-whole-struct-copy.md),
[copy IR](../ir/struct-copy.md) and qualification.
