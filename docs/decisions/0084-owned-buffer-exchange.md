# 0084: Exchange initialized owned buffer storage

Status: implemented and qualified in ASTRA-OWN-SWAP-1; see the
validation report.
The actual decision registry ends at 0083 on accepted commit
`1a03559c60ca34b9cf46183e0bb0854352b05683`.

## Context and checkpoint

APP-CAD-2's complete idiomatic route is accepted. Its source, recipe, numerical
expectations and receipts remain I0. Its rotation uses a record temporary and two
assignments for each 72-byte Kernel: two reads and two writes, or `288*K` logical
bytes per rotation. This is an observed composition cost, not an application block
or a measurement of DRAM traffic.

The accepted witness is `build/app-cad-2/friction.astra`, recovered from the
verified records archive after the user's build cleanup. Its SHA-256 is
`4c5bd77135b961ffd09fe5dfc9058cd70976a10d4f8331b44e16a8dd7c421903`.
Both retained baseline compilers reject it at the parser, including `--parse`:
moving ownership out of an owned field is unsupported; move requires a named
owner. Fresh compilation and execution of the actual accepted element-copy
rotation succeed. The baseline compiler and accepted strict compiler have
different bytes and are recorded separately in the campaign evidence.

The audit found an existing complete buffer group, stable local owner identity,
declared cleanup responsibility and native class field-layout authority. Consuming
parameters acquire local owner slots. Constructor field initialization is checked
separately. Field receiver syntax is bounded to the receiver forms already admitted
by Core construction; this decision adds no call-result member syntax. Existing
pending field borrows conservatively protect containing-class aliases during
argument, indexed destination and indexed receiver evaluation.

An ordinary two-slice function loses the identities of the owning slots. Public
moves would require an uninitialized field and a caller repair obligation. Neither
represents the required operation. A dedicated statement can capture two checked
destinations and perform one complete descriptor permutation while preserving
both initialized owners. This is representable within the existing domain.

## Decision

Reserve exact lowercase `swap` in native source and add:

```astra
swap(this.state, this.next);
```

Both operands must be live, initialized, writable owning buffer slots of the
same canonical SliceType and concrete cleanup contract. Named owned locals,
consuming parameters and initialized native class fields qualify. The word makes
ownership intent explicit; operands have no `move` annotation. Existing moves,
calls, assignments and library `swap_elements` retain their contracts.

Resolve and check the left destination once, then the right once. Protect the
captured storage and its containing object across later evaluation. After both
checks, capture both complete pointer/count groups before writing either group.
No source effect or fallible operation may interrupt the capture/store region.
The operation reads and writes no payload and performs no allocation or cleanup.

Same physical slot aliasing is valid after both evaluations and checks. Distinct
owners of one allocation remain invalid ownership construction. Empty allocated
owners remain live; physical null/zero is not a dead-slot proof. Different counts
travel with their matching pointers. Cleanup responsibility stays with each slot,
including reverse field cleanup after user deinit.

Invalidate dependent borrows of both slots, conservatively including containing
object aliases. A borrowed class receiver alone is not a payload slice borrow.
No borrow survives by following an allocation to another scope. Known self-swap
does not relax this initial rule.

Generic bodies use the existing signature-derived GEN-BUFFER premises. Exact
lexical `T[]`/`U[]` conflicts reject before demand, even when a caller might supply
equal types. Materialization remaps places, owners, receivers and cleanup contracts
before CFG. No new constraint, key component, ownership domain or ref/inout API is
introduced.

CFG and SSA represent destination captures separately from a bounded exchange.
Captures are neither payload views nor owners. Independent verifiers check ordered
dominance, exclusive correspondence and absence of intervening invalidation.
LLVM uses existing descriptor storage and ordinary scalar loads/stores. Copied
plans and raw LLVM bindings check exact slot membership and complete opposite
snapshots without retaining executable predecessor graphs.

## Compatibility and scope

The native exact-word reservation is intentional. The initial tracked-source
survey found no native callable, variable, field or type named `swap`; Python
test labels mentioning the existing `swap_elements` algorithm do not collide.
Foreign cname strings, other case spellings and the independent VAPI lexer are
unchanged. Final inventory reconciliation found zero inherited expectation
supersessions; all 1,041 static expectations remain covered.

No field extraction, owning struct fields, nullable owners, Resource/Class owner
exchange, generic classes, new buffer element domain, ABI profile, helper import,
runtime ownership flag or public mutable reference is authorized. This is a
synchronous language-effect guarantee, not hardware or thread atomicity.

I1 must be a separately versioned minimal rotation experiment with exact logical
parity and an explicitly permuted allocation ledger. Existing I0 timing gains are
not credit for this operation. Feature and application qualification are reported
separately; neither is PASS before its required evidence exists.
