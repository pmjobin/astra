# Explicit allocation policies and the selected no-OS profile

A unique Class keeps its existing owner, move, borrow, destructor and nullable
reference rules. An explicit declaration policy chooses where a dynamic owner
gets storage and how that storage is reclaimed. Unannotated Classes retain
their existing hosted allocation and ABI. Policies add no mandatory object
header, implicit sharing or process-wide allocator.

```astra
[Allocator(kind="pool", domain="telemetry.samples", capacity="4096", blocks="64")]
[Align(bytes="64")]
class Sample {
	int value;
	init(int value) { this.value = value; }
	deinit() {}
}

int main() {
	var sample = try_new Sample(42);
	if (sample == null) { return 1; }
	return sample.value;
}
```

The initial policy family applies to exact nonpolymorphic Classes, including
eligible closed generic containers. Inheritance, interfaces and exception
roots reject a policy. Every later compiler stage owns and verifies an
admitted snapshot of its kind, domain, budgets, alignment and callback names.
Policy allocations remain observable at O2 and are excluded from automatic
stack promotion. Lexical `Sample.init(...)` retains caller storage and its
ordinary cleanup; it does not consume a pool slot.

| Kind | Storage and reclamation | Admission |
| --- | --- | --- |
| `heap` | Explicit aligned hosted heap domain; matching release after destructor | Capacity/blocks are omitted; host allocation may fail |
| `region` | Statically backed bounded arena; individual owners run their destructors, and the bump position resets after the last release | Explicit byte capacity and live-block budget; alignment padding consumes capacity |
| `pool` | Statically backed equal-size slots; release permits safe reuse with monotonically increasing generations | Capacity/blocks must give a power-of-two stride that can satisfy the requested object |
| `static` | One statically backed live allocation | Byte capacity; blocks defaults to one |
| `custom` | Statically backed bounded domain; a checked native scalar callback proposes placement inside it | Runtime independently checks offset, alignment, range, overlap and reentry |

Domain names are ASCII identifiers with optional dots, up to 128 bytes. A
non-heap domain has capacity 1..16,777,216 and 1..4096 block descriptors, no
more descriptors than bytes. Classes may share a named domain only with the
same kind, capacity, block budget and callback identities. Individual Class
alignments may differ. `[Align(bytes="N")]` selects a power-of-two minimum up
to 4096; the effective allocation/caller alignment also respects the target's
natural alignment. It does not change the Class's native field layout.

These bounded domains have **static backing lifetime**. Returning or moving a
valid dynamic owner preserves that lifetime. No dynamic, shorter-lived region
or escaping raw domain pointer is introduced. Existing lexical/caller loans
cannot escape. Internal reset refuses while any allocation is live, and reset
never recycles generations or cumulative counters. The compiler owns every
destructor and matching release. Source cannot declare the reserved
`astra_alloc12_` runtime symbols.

`try_new` returns a legitimate null owner on failed admission and skips hidden
initialization and the constructor. Supported sites are synchronous and accept
unmanaged integer/floating/bool values and exact owned Class/Resource inputs.
For a named owning input, the source slot must be nullable. Refusal preserves
its original value and release authority with the caller. Admission transfers
the payload to the constructor and leaves an empty nullable owner in that
caller slot. Checked initialization failure rolls back consumed inputs and
initialized fields exactly once; the caller slots stay empty. Ordinary `move`
outside this conditional admission keeps its existing consumed-state contract.
Borrowed, buffer and by-value aggregate constructor inputs to `try_new` still
require additional admission contracts. Argument evaluation and checked errors
keep their ordinary order. A `nonnull` destination needs a real null-branch proof.
Ordinary `new` retains fatal allocation failure, including for an annotated
Class. Bounded container `reserve` returns false on failed growth and leaves
the original backing, capacity and live owners intact.

Nested owning record leaves, owned child fields, slot elements and Shared
payloads retain each exact Class's policy. A container's backing has its own
container policy; growing slots moves owner handles, not live Class objects.
Shared/Weak control blocks retain their existing explicit hosted strategy and
single-threaded meaning. An owning Closure environment's policy also supplies
its carrier. Retained callback release still requires observed provider
quiescence before destroying the environment and reclaiming both allocations.
General nondefault async frame placement is outside this initial profile.

For custom placement, `allocate="name"` nominates a native C export
`int(int bytes, int alignment, int suggested_offset, int capacity)` and
`release="name"` nominates `void(int offset, int bytes)`. Both have static
code lifetime in the same checked compilation unit. Negative placement means
exhaustion. A callback cannot publish an arbitrary pointer or grant ownership;
the runtime validates its proposed offset before publication. See
[A103](../../examples/freestanding-allocation-12/a103-policy-identity.astra).
Callbacks do not grant thread safety or C-unwind permission.

`[Repr(layout="C")]` admits declaration-order natural LP64 scalar POD records
with 1..32 integer/f32/f64 fields. Bool, pointers, nested/owning fields, methods,
properties and native Classes reject. An optional record Align is a minimum
no greater than natural C alignment; greater record alignment rejects. C
import/export still needs the established explicit `natural-lp64` or finite
by-value boundary. The compiler independently verifies types, offsets,
padding, complete size and alignment. See the
[GCC/Clang C oracle](../../tests/freestanding-allocation-12/layout-oracle.c).

Native module declarations preserve Allocator/Align/Repr attributes under the
existing compiler, interface, type-layout and object fingerprints. Compiler
domain globals have a separately enumerated exact identity; no arbitrary
public implementation symbol is admitted. Heap/region/pool/static policies
compose across the selected native unit boundary. Custom callback policies
remain within one checked compilation unit.

The approved executable no-OS selection is `--runtime=none
--target=x86_64-none-elf`: QEMU 10.2.2 `pc-i440fx-10.2`, TCG `qemu64`, 64 MiB,
SeaBIOS, an explicit Multiboot loader, COM1 and deterministic debug exit. It
supports selected scalar numeric/record/lexical Class code and bounded
non-heap policy owners. The authored core memory primitives and allocation
substrate are explicit link inputs. Scalar SSE/SSE2 startup establishes the
selected f32/f64 environment. Vector target execution remains separately
gated. Hosted text/resources, system heap, providers, Shared/closures, async
and exception unwinding remain unavailable in this no-OS profile.

Fixed compiler-recognized PC device operations provide volatile EDU registers,
COM1 byte output, aligned I32 atomics on one separate RAM word with named
orders, and a checked breakpoint entry/IRETQ path. They grant no arbitrary
MMIO address, cross-thread allocator guarantee or general interrupt ABI.
Evidence is for the approved emulator model, not physical silicon. AArch64
remains integer object-only; SH-4 and self-hosting remain deferred.

See [ADRs 0159](../decisions/0159-selected-no-os-pc-target.md),
[0160](../decisions/0160-general-allocation-authority.md),
[0161](../decisions/0161-checked-pc-device-policies.md), and
[0162](../decisions/0162-fallible-construction-and-pod-layout.md), plus the
[application/recipe inventory](../../examples/freestanding-allocation-12/README.md).
