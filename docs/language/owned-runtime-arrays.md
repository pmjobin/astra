# Owned runtime arrays

[Struct elements](struct-elements.md) add concrete record elements under the same
owner/view type identity and lifetime rules. Their native boundaries use
[struct-elements-v11](../abi/native-struct-elements-v11.md); numeric boundaries
retain buffer-v8/slice-v5. Whole-element reads are independent value snapshots.

Plain native Resource/Class parameters now join SliceType in using the
[default bounded borrow](parameter-borrowing.md). Numeric buffer-to-slice calls
keep slice-v5 and numeric `owned T[]` transfers keep buffer-v8. Borrowing preserves
owner usability; a live same-owner borrow plus transfer in one invocation rejects.

`owned T[]` is a uniquely owned runtime-sized array. `T[]` remains a borrowed
view of the same canonical `SliceType<T>`. Ownership is a contract attached to
the binding or boundary, not a second slice type.

```astra
void initialize(f64[] samples) {
	int i = 0;
	while (i < len(samples)) {
		samples[i] = 1.0;
		i = i + 1;
	}
}
owned f64[] make(int count) { return new f64[count]; }
owned f64[] relay(owned f64[] samples) { return move samples; }
void run(int count) {
	owned f64[] samples = make(count);
	initialize(samples);
	owned f64[] next = relay(move samples);
	next = new f64[len(next) + 1];
}
```

The existing length surface is **`len(samples)`**, returning `int`/`i32`.
Each allocation has a fixed length. Assignment replaces the entire owned array;
it does not resize an allocation.

## Elements and initialization

The element authority requires concrete fixed native storage, trivial
destruction, a defined zero and ordinary copyability. BUFFER-1 admits these 34
canonical types; `int` and `i32` name the same one:

| Elements | Admitted vector lane counts | Initial value |
| --- | --- | --- |
| `bool` | 2, 4, 8, 16 (masks) | false in every lane |
| `i8`, `u8` | 2, 4, 8, 16 | integer zero in every lane |
| `i16`, `u16` | 2, 4, 8 | integer zero in every lane |
| `int`/`i32`, `u32` | 2, 4 | integer zero in every lane |
| `f32` | 2, 4 | exact positive zero, including every vector lane |
| `f64` | none in the current numeric inventory | exact positive zero |
| `void*` | none | null |

Scalars in every row are admitted. Existing numeric/mask vector spellings such
as `owned f32<4>[]` and `new bool<16>[count]` are unchanged. Astra currently has
no concrete `i64` or `u64` source types; BUFFER-1 does not introduce them.

| Rejected element domain | Reason |
| --- | --- |
| Resource/HandleType, ClassType | Ownership-bearing/nontrivial element lifetimes are deferred |
| Incomplete, empty, cyclic or ineligible structs | Every recursive field must satisfy the concrete storage, copy, zero and trivial-destruction rules |
| SliceType and fixed ArrayType | Nested array/view storage is outside the element domain |
| Typed pointers, including `int*`, `f32*`, `f64*` | Buffer element admission is limited to opaque `void*` |
| Unresolved element types below concrete Core | Generic element proofs must materialize to concrete storage and zero authority before CFG |
| `void`, unsupported vector shapes | No admitted concrete element storage |

Eligible ordinary and concrete generic-origin structs recursively containing
the table's leaves are also admitted. Eligibility is not the generic-argument
capability GEN1_PLAIN_COPY: copying alone does not establish allocation authority.
[Generic owned arrays](generic-owned-arrays.md) reuse the complete element proof
for direct T[] parameters, owned results, explicit local owners and new T[count].
Eligible record value transport follows [GEN-COPY](generic-copyable-values.md).

`new T[count]` evaluates an exact `int` count and creates one unique owner. A
negative count traps before allocation; negative literals reject during checking.
Byte-size overflow traps. Unannotated nonempty allocation failure traps; an
optional [allocation-failure action](allocation-failure.md) selects a fatal call
only for allocator null and traps if that call returns. Ordinary `new` always
initializes every element; no unsafe uninitialized path exists. Floating zero is
bit-exact `0x00000000`/`0x0000000000000000` on the qualified backend.

Zero length is valid and canonical: null base, length zero, no allocator call.
It is an empty array, not a nullable owner. Empty cleanup is a no-op. Indexing it
traps. No header, capacity word, refcount or runtime cleanup pointer is stored.

## Indexing and borrowing

`samples[index]` reuses checked Slice element Places: `0 <= index < len(samples)`
must hold before address use. Elements are writable under the existing writable
slice alias policy. A borrowed parameter receives the same storage and length;
mutations remain visible to the owner. Borrowing neither allocates nor copies.

```astra
void process(f64[] samples) { samples[0] = 2.0; }
void f() {
	owned f64[] samples = new f64[3];
	process(samples);                   // implicit bounded borrow
	owned f64[] next = move samples;    // borrow has ended
}
```

`borrowed T[]` remains accepted. Plain `T[]` parameters imply the same nonescaping
contract. An owner cannot initialize persistent borrowed storage (`T[] view =
owner`), and a fresh owning producer cannot disappear into it (`T[] view = new
T[n]`). Existing slice results/escape restrictions remain in force. Moves or
replacement observable during a live borrow reject; ambiguous containing-class
alias cases use OWN-FIELD's conservative rejection policy.

## Lifetime, transfer and replacement

Each local or owned parameter has one stable cleanup slot. Ordinary scope exit,
return, break and continue release live contents in existing lexical cleanup
order. Traps do not unwind. Owner transfer transports only base and length.

[Owned buffer exchange](owned-buffer-exchange.md) adds the explicit statement
`swap(a, b);` for two live initialized owner slots of exactly the same buffer type.
It exchanges complete base/count descriptors, including differing counts and empty
owners, without accessing elements. Both slots retain their cleanup rank and stay
live. Dependent borrows of either slot must end first. Initialized native class
fields qualify; direct field move-out remains rejected.

Copying an owner rejects. Named native ownership transfer requires `move`.
Afterward indexing, length, borrowing and another move through the source reject.
The source may physically contain null/zero but remains semantically MOVED.
Owned call arguments retain OWNBOUND's bounded `move named_owner` form. Direct
allocation/result producers are accepted by owning initialization, replacement
and return; inline producer arguments are not added by BUFFER-1.

Mutable concrete Resource and buffer locals/parameters support automatic RAII
replacement. The incoming producer is evaluated and captured first; named source
transfer commits; then old live destination contents are cleaned and the complete
new payload is stored. RHS failure leaves the old destination untouched before
the trap. A MOVED/RELEASED destination rearms without old cleanup. Self-move
rejects. Explicit local/parameter `release` is available for intentional early
destruction, followed by ordinary rearm. ClassType owner assignment is unchanged.

Native factories may return `new T[n]`, `move owner`, or a direct exact owned
factory result. Callers may initialize or replace a local/field directly from
such results. Successful result transfer disarms the producer's cleanup. Discard
and capture by a borrowed destination reject; no intermediate owner is required.

## Class storage

```astra
class Context {
	owned f64[] samples;
	int count;
	init(int count) {
		this.samples = new f64[count];
		this.count = count;
	}
	void run() { initialize(this.samples); }
	void replace(int count) { this.samples = make(count); }
}
```

Ownership-bearing classes require explicit `init`. Every field must initialize
exactly once on all normal constructor completions; missing, duplicate and early
reads reject. Allocation, moved exact owners and owned factory results are valid
sources. Field indexing and `len(this.samples)` work normally.

Replacement validates the receiver before incoming production/consumption. It
captures the incoming owner before freeing the current field. Object aliases see
the replacement. Field move-out, field-to-field move and explicit field release
are deferred, preserving continuously initialized owner slots.

User deinit sees live fields and may replace them directly or via methods and
ordinary scalar setters. After normal deinit return, current Resource and buffer
fields clean in one reverse declaration-order sequence. Deinit traps and partial
construction do not unwind. OBJ-RET and generic Ownable containing-class transfer
preserve exact ObjectStorage and field contents.

Owned buffer properties, resize/reserve/append/realloc, custom allocators, arenas,
RAII elements, shared buffers, C array ABI,
C floating pointers and aggregate Move are not part of BUFFER-1.

GEN-BUFFER-1 adds direct generic `owned T[]` and `new T[count]` under exact
signature-derived premises, without expanding the element domain or changing the
concrete operations above. See [generic owned arrays](generic-owned-arrays.md).

INFER-1 adds `var samples = new f64[count];` and inference from exact owned
buffer results or `move samples`. These are equivalent to explicit `owned f64[]`
locals: the semantic type remains canonical SliceType, with the same static
native-buffer-deallocate contract, RAII replacement, release and lexical cleanup.
`var alias = samples;` rejects. Fields and API ownership boundaries remain
explicit. See [local inference](local-inference.md).
