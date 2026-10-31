# Systems and DSP profiles

Astra's hosted compiler remains a Vala/GLib application. Its output selects
dependencies according to the source and the explicit runtime profile.

## Runtime-free objects

`astrac --target-info` prints the selected triple, data layout, pointer width,
baseline CPU/features and supported runtime selections. Default compilation is
hosted. `--runtime=none -c` admits a closed numeric/control/fixed-storage subset
and produces an object for an explicit external startup/link route. It rejects
classes, resources, text, exceptions, async, heap buffers, foreign providers and
native module interfaces before emission. LLVM declarations are checked before
and after optimization for hidden hosted helpers.

The qualified execution profile is **Linux no-libc**, x86-64 GNU LP64. The
[CRC example](../../examples/systems-dsp-9/a65-crc.astra) implements CRC-32 in
Astra. Its [entry shim](../../examples/systems-dsp-9/linux-start.S) aligns the
stack, calls the C export and exits through Linux syscall 60. It has no CRT,
libc, dynamic interpreter or dynamic libraries. It depends on Linux.

`--target=aarch64-none-elf --runtime=none -c` is a separate **OBJECT_ONLY**
profile for scalar integers of at most 32 bits and bool, with an explicit C
integer export boundary. Unsupported target, CPU, ABI and provider combinations
fail closed. An inspected AArch64 object establishes emission, not execution.
SH-4/Dreamcast and actual no-OS execution remain unqualified.

## Exact short vectors

`f64<2>` has exactly two binary64 lanes and a 128-bit payload. It uses the
existing vector grammar, lane/mask operations, fixed arrays, typed pointers and
native function channels. It supports ordinary lane arithmetic and comparisons,
with no implicit element conversions, fast math or FMA contraction. Numeric
vectors remain at most 128 bits. `i64<2>` and `u64<2>` extend the same family;
`isize` and `usize` vectors remain excluded.

`sat_add` and `sat_sub` use exact signed or unsigned saturating semantics.
Overflow clamps to the type's mathematical endpoints. It does not wrap, trap,
change signedness, or acquire floating behavior. The extended 64-bit vectors
use exact baseline sequences where a direct ISA instruction is unavailable.
Packed-double and PCM16 instruction claims have independent disassembly checks.

The numeric oracle checks 2,048 deterministic vector cases, including signed
zero, subnormals, infinities, NaNs and integer extrema. Finite and infinite
results compare by bits; NaNs compare by classification. NaN payload identity
and universal cross-ISA reproducibility are outside this qualification.

## Typed arena records and unique resources

ByteArena now supplies `read_u32_le`, `write_u32_le`, `read_u64_le` and
`write_u64_le`. An operation validates the ID, complete field extent and natural
offset alignment before accessing any bytes. The encoding is explicitly little
endian and does not reinterpret the byte buffer as a native struct or pointer.
The existing checked capacity, monotonic IDs, LIFO release and zeroed reuse
contracts remain authoritative.

`packet_arena(capacity)` creates the finite `PacketArena` profile. Two typed
`ArenaPacket` records each contain `u32 tag` and `u32 payload`, at offsets 0 and
4 with stride 8 and admission alignment 4. Each admitted record requires one
exact unique `PacketResource`. Two compiler-managed owner fields form its
resource side table. `append(packet, move resource)`, `read(id)`, `offset(id)`
and `drop_last(id)` preserve ID and ownership identity. A read returns a copied
POD value. No arena pointer or borrowed storage view escapes.

Successful placement acquires no packet heap allocation. The arena's initial
receiver/backing allocation remains hosted; checked capacity exhaustion is
separate from fatal underlying allocation failure. A failed admission retires
the transferred resource once. LIFO release validates before changing resource
ownership. Scope exit, checked exceptions, early return and consuming the arena
retire all remaining resources through ordinary ownership cleanup. Resource
extraction, arbitrary owning aggregates and general Class/Bag allocator
substitution are outside this finite profile.

The supplied application provider opens real file descriptors using a static
resource table. It is an explicit external resource boundary, while record
storage, checks and ownership composition are authored in Astra.

## Volatile memory places

`volatile_load(place)` and `volatile_store(place, value)` operate on exact
`u32` or `u64` indexed array/view places or checked typed-pointer dereferences.
The ordinary Place retains bounds, origin and lifetime authority. Volatile
accesses additionally check natural alignment and retain typed LLVM volatile
flags through O0/O1/O2. Raw foreign addresses cannot be reinterpreted into this
API. Invalid dynamic bounds, null dereference and misalignment trap according
to the existing fatal memory-access policy.

The host fixture uses real anonymous mapped pages. Four hardware watchpoints
observe the exact nine-access sequence at O0/O2, and LLVM plus disassembly
confirm retained widths and operations. Volatile does not provide atomicity,
thread synchronization, cache flushing, DMA ordering, interrupt binding or
physical peripheral correctness.

See the [qualification recipe](../../tools/qualification/systems-dsp-9.md) and
[design scope](../systems-dsp-9-design.md) for commands and remaining gates.
