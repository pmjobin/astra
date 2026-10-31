# API A: native byte-processing SDK

API A is qualified on Linux and native Windows. The first frozen API B challenge
exposed a generic GIR empty-parameter-list bug; its failure is preserved. After
the general repair and API A requalification, a replacement freeze precedes the
new API B2 challenge. That SDK challenge passed but final integration exposed
two general compiler regressions. The repairs, new strict build and API A
requalification precede freeze three and the new float-record/signal B3 challenge. See the current [interop guide](language/declaration-driven-interop.md).
Its unique C processing Session owns configuration, an independent latest snapshot
and revision/statistics state. A Shared service component owns that unique processor
and exposes target-selected C/COM/GObject views of one service instance. The byte
algorithm occurs only in the native leaf implementation.

For each byte, XOR with the checked mask (0..255), then optionally rotate the
8-bit value left by one bit. Each successful process call increments revision,
adds input length to processed count, and adds the output-byte sum multiplied by
the configured weight (finite 0..16) to score. Statistics use a closed generic
`Statistics<f64>` record. Configuration failure and insufficient output capacity
leave the previous state and snapshot intact. The foreign bounded-output bridge
publishes staged output only on success. Snapshot results are independent owners.

The independently authored C oracle fixes vectors before execution. With mask 85,
rotation enabled and weight 2.5, `[0,1,254,255,0,128]` produces
`[170,168,87,85,170,171]`, revision 1, processed 6 and score 2127.5. A second
`[3,0,254]` produces `[172,170,87]`, revision 2, processed 9 and cumulative
score 3200. Empty input succeeds with a new revision. Invalid configuration,
NaN weight, insufficient capacity and null/nonempty input are explicit checks.

The shared service exposes integer, bool, double, NUL UTF-8 text and nullable
object properties. A scalar processed signal and an object/text snapshot-ready
signal originate in native methods after state commit. C and GI consumers retain
the token and text beyond service retirement; self-disconnection observes deferred
closure destruction. The scanned GIR generates a native Astra consumer with owned
text/bytes/object channels and a retained typed scalar Closure.

The Linux recipe compiles the leaf, component and adapters at all eight O0/O2
combinations plus O1 smoke. Task-owned producer copies are removed before dependent
compilation. SDK headers, library, typelib, GIR and pkg-config metadata are staged
outside the checkout. Independent C, generated-header C, native, C/GObject and GI
clients execute there. Selected O0/O2 clients receive unsuppressed Valgrind checks.
Exact source, compiler, products, commands and outcomes accompany each recipe run.

The same source declarations select C+COM on Windows, C+GObject on Linux and a
native-only personality. Windows SDK generation and native execution are separate
checks; a successful cross-build alone receives no native execution credit.

Opaque Windows exception descriptors use image-local hidden visibility. These
compiler-pinned native units link within the same executable or library image;
native descriptor sharing across independently linked DLL images is not qualified.
The LLVM verifier independently retains the exact visibility of defined and
imported descriptors. A detached mutation removes it from otherwise valid LLVM
and must reject. Public COFF symbol validation remains exact; no wildcard
reference-symbol admission was added.

The fresh release compiler uses the existing strict C profile with warnings as
errors, assertions enabled and both optional hosted runtime profiles enabled.
Initial strict attempts exposed generated const-qualification errors in newly
added metadata string properties. Explicit backing fields preserve the same
contracts and mutation checks without disabling diagnostics. Earlier builds and
failed Windows assertions remain retained as intermediate evidence.

Supplementary sanitizer qualification instruments actual emitted Astra IR with
ASan after applying the compiler's exact reported target and data layout, and
instruments C/GObject glue with ASan/UBSan. Installed GLib/GObject is outside that
instrumented region. The initial unknown-target instrumentation attempt used an
incorrect ASan shadow mapping and is retained separately from the corrected run.

The retained runtime also receives a narrow Helgrind check of callback retirement
and forbidden-thread calls. With standard Valgrind suppressions, the witness has
zero reported errors and one suppression, `helgrind-glibc2X-110`. Disabling those
standard suppressions reports a libc thread-join access; the standalone
`glib-thread-join-probe.c` reproduces that same report without Astra runtime code.
The unsuppressed Helgrind and DRD attempts remain retained. This is evidence for
the stated constructing-thread protocol, not a claim of general method-state
race freedom or zero library findings with suppressions disabled.
