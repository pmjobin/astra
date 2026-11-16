# Hosted and freestanding calculations

Choosing a runtime is part of a program's design. A calculation over fixed
integers can require far less support than text I/O, owning collections or
recoverable errors. Begin by identifying the program's actual imported symbols
and selected libraries, instead of assuming the compiler's LLVM dependency is
also a mandatory dependency of every emitted program.

This complete fixed-array calculation has a statically exact collection count:

```astra example=fixed
language astra27b;
int main() {
	int[4] values = (0..4).collect_fixed();
	return values[0]+values[1]+values[2]+values[3]+36;
}
```

The four values are zero through three, so their sum plus 36 is 42. The test
runner links the same object both conventionally and with a small Linux x86-64
syscall entry, using `-nostdlib -static` and no libc/allocator. It checks no
dynamic interpreter and no undefined symbols, executes both target modes and
checks strict returning memory. The syscall startup is durable recipe source
in the test runner; it is specific to this host ABI.

## Where the boundary changes

Changing `collect_fixed` to `collect_array` requests owning runtime allocation.
It is a different resource requirement, even when the elements and arithmetic
are identical. The existing freestanding range suite also verifies that an
owning collection cannot link without its allocator. The formatting example
selects additional runtime definitions and providers; file I/O selects its real
C implementation. Those dependencies are concrete, rather than a default
framework attached to every executable.

For numerical work, exact scalar types and arrays provide a useful starting
point. Modern native vector code is not qualified merely because older bootstrap
SIMD tests passed. [Types](../reference/types.md) and [Limits](../reference/limits.md)
describe the current refusal. This chapter makes no CPU-throughput claim, C++
comparison, hardware/device claim or new optimization promise. Performance work
belongs to milestone 28-B with independent measurement and semantic baselines.

“Freestanding” here means this selected no-runtime native link and execution.
It does not mean qualified firmware, an interrupt handler, a portable syscall
interface or an arbitrary target architecture. Keep those limits attached to
the evidence when reusing the example. The compiler's independent ownership and
physical checks still apply even when the emitted program has no heap.
