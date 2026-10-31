# Explicit C union projections

The selected GNU x86-64 Linux LP64 profile passes real C unions by value through
an explicit, fixed active-member projection. A Source record exposes exactly one
member. Other C members remain inaccessible through that record type.

```astra
[Repr(layout="C-union",members="integer:i64,bits:u64",active="integer")]
struct SignedWord { i64 integer; }
[CImport(name="parse_integer",header="packet.h",record_abi="value-lp64")]
SignedWord parse(SignedWord input);
```

The independent C declaration is a union such as
`union Word { int64_t integer; uint64_t bits; };`. Its extent/alignment are 8/8
and its SysV classification is one INTEGER eightbyte. The admitted member list
has 2–8 unique C identifiers with `i64` or `u64` types. The selected Source field
must match the active member's name and exact signed type. A separate unsigned
projection can expose `bits`. They are distinct nominal Source types; assignment
and implicit conversion between them reject. No inactive-member read, type
punning, pointer alias or representation cast is supplied by this profile.

The C provider must return and consume the declared active member, as with other
trusted foreign contracts. An untagged union cannot reveal its active member at
runtime. Use the tagged form when the provider supplies a discriminator:

```astra
[Repr(layout="C-tagged-union",members="integer:i64,bits:u64",
	active="integer",tag="1")]
struct SignedPacket { i64 tag; i64 integer; }
```

This projects `struct { int64_t tag; union Word payload; }`, with tag at offset
0, payload at offset 8, extent 16 and alignment 8. The leading Source field must
be `i64 tag`; the selected case is an explicit decimal 0–2147483647. C import
arguments and results and C export arguments and results all check that tag
before crossing into the other domain. A mismatched tag is a contract violation
and traps before exposing a typed payload or forwarding a bad argument. The
Source program may inspect a discriminator separately and select the matching
typed provider entry. Changing a tag does not change its projection type.

Use `record_abi="value-lp64"` for imports and exports. Borrowed mutable union
pointers reject: a C write could silently change the selected member. Floating,
mixed ABI-class, smaller, nested, packed, owning and dynamically changing union
projections remain unsupported and diagnose. Ordinary native record layout and
existing `Repr(layout="C")` contracts retain their prior meanings.

The active list/member/tag are part of the frozen representation identity through
checked semantics, Core, CFG, SSA, native ABI and C ABI. LLVM bindings verify the
actual tag comparison, complete tag/payload extraction and insertion, forwarding
call and admission branches, after releasing upstream graphs.

`tests/interop-tooling-14/c-unions.py ASTRAC EXTERNAL_OUTPUT` compiles strict C11
GCC and Clang producers/clients with independent `_Static_assert` layout checks.
It executes signed/unsigned unions and tagged unions in both directions at
O0/O1/O2, rejects all four wrong-tag boundary directions, and runs unsuppressed
O0/O2 Valgrind. The foreign contract proof mutates every compiler stage and
ordinary-LLVM-valid tag/branch operations, restoring healthy output after each.
