# ADR 0071: Opt-in numerical base library

Status: accepted for ASTRA-BASELIB-1. Baseline:
`63ab1eaf5076eced5e2d12f8bc88dc656e9b7b3c` (GEN-INFER-1).

## Decision

Ship ordinary Astra sources under `lib/astra/base`, optional hosted sources and
VAPI under `lib/astra/hosted`, and explicit static platform adapters under
`lib/astra/platform`. No source is injected automatically. All source functions
share the existing global declaration space; no file has private visibility.
The provisional `astra_base_` helper prefix is a convention, not a reservation.

`min` and `max` require only Ordered and use ordered self-comparison to select
NaNs before comparing operands. They select the first operand on ties, including
signed zeros. `clamp` validates ordered bounds before selecting an operand.
Classification uses ordinary comparisons and exact suffixed finite limits.

Assertions are eager, always-on ordinary functions. A false condition and invalid
clamp bounds call the ordinary imported C function
`extern(C) void astra_base_fail(int kind, int code);`. Its library contract is
abnormal, non-returning, non-unwinding termination. Neither the spelling nor this
document gives the compiler a noreturn attribute. Core and floating equality
assertions are separate components. Hosted reporters expose typed scalar values
and floating representation bits; caller locations and arbitrary messages remain
absent.

Exactly one failure provider is linked. The trap provider is qualified by its
object and a linked CRT/libc-free witness on GCC x86-64 Linux. The hosted provider
uses stderr and abort; libc internals are outside any allocation guarantee.
No weak linkage, callback, registry, recovery or implicit provider exists.

Math consists of ten ordinary VAPI declarations, selecting C float/double
functions through existing CCode metadata. Explicit `--link-library m` requests
the host driver's `-lm`. Bare names follow `[A-Za-z0-9][A-Za-z0-9_.-]*`.
Object and library inputs form one ordered, repeatable, shell-free argv sequence
after the generated object and before the driver's existing `-o` pair. Existing
check/dump rejection of executable-only link inputs is retained.

## Alternatives and boundaries

An internal compiler trap is not a public language operation. Adding public trap
syntax, name-recognized assertions or an implicit runtime would expand the
language and obscure dependencies. The explicit C hook fits the accepted exact
I32 boundary and permits a future board-specific static implementation.

C fmin/fmax have different NaN/tie policies and cannot implement the specified
generic contract. Ordinary source selection preserves operand types and gives
integer extrema no arithmetic-overflow case. The current Ordered domain is the
six integer types plus f32/f64; aggregates, vectors and masks do not gain it.

A linker-flags escape hatch or automatic VAPI autolinking would enlarge policy
beyond hosted math. One narrow named-library option is sufficient; it provides
no search paths, packages, transitive resolution, rpath or optimization options.

GEN-INFER-1 exact outer-parameter propagation, staged ownership proof commitment,
explicit moves and inline-owned-argument rejection remain intact. No parser,
capability, Core/CFG/SSA, ABI or LLVM numerical implementation changes.

## Consequences

Clients explicitly select sources, metadata and support. Pure numerical use has
no undefined runtime symbols. Contracts can terminate without libc. Hosted
diagnostics and math select system facilities and retain CABI-FP target gates.
The ordinary executable CLI still uses the host CRT; the separate freestanding
qualification uses an explicit Linux startup witness, not a new driver mode.

Detailed contracts, actual commands and measured results are in
[the library guide](../library/base.md), [numerical contracts](../library/numerical-contracts.md),
[providers](../library/failure-providers.md), [hosted math](../library/hosted-math.md)
and qualification.

Const/immutable bindings; strings/interpolation/formatting; caller file/line or
expression capture; debug assertions/elision; approximate equality; namespaces,
modules/packages; overloads/new capabilities; generic containers/aggregates;
process arguments; RNG/transcendentals/bespoke libm; new C types/pointers/varargs;
heap objects/refcounts/weak references; and a mandatory runtime are deferred.
