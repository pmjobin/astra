# Surge 11 numerical applications

These twelve distinct public-driver programs pass the finite Surge 11 N1–N9
contract. See qualification
and the ledger. This does not
claim execution of every historical A01–A84 application.

| Application | Algorithm / current component evidence |
| --- | --- |
| A85 stencil | 48,003 samples, offset vector views, shuffle and scalar tails; exact C lane oracle and output bytes |
| A86 mask mixer | 4,096 lanes with NaNs, infinities and signed zeros; exact C selection oracle |
| A87 PCM | 48,000 two-track signed PCM samples with explicit clipping extrema; exact C integer oracle |
| A88 FIR | 17 taps over 48,000 samples, fragmented blocks, explicit midpoint reset and empty-filter control; independent C convolution |
| A89 biquad | Two strict stateful stages over 48,000 samples with fragmented blocks, denormals and reset; exact C recurrence |
| A90 DFT | 32 independent length-64 complex transforms, strict and contracted source modes; independent long-double trigonometric reference, absolute bound 2e-10 |
| A91 geometry | 24,000 offset two-dimensional points through Matrix2; exact C reference and output bytes |
| A92 policies | 7,435 f32/f64 arithmetic observations per O level, policy negatives, checked-domain traps and separate FMA feature audit |
| A93 packet | 48,000 temporary owners, early returns, exact teardown/output bytes; returned-owner and 425 independently counted checked-failure cases retain allocation |
| A94 metadata | 375 cached attenuation records over 48,000 samples; readonly promotion, mutation and side-effecting factory controls |
| A95 pipeline | 12,000 multi-handler items; dynamic/exact interface calls, generic specialization, retained Closure, Shared field borrowing and Weak expiration |
| A96 stream | Independent native producer/consumer processes; 192,000 samples, FIR plus cascaded biquads, strict/selected policies and midpoint reset |

A85–A96 component executions pass public O0/O1/O2 and unsuppressed Valgrind.
Each has a meaningful source or runtime refusal counterpart. Binary observations,
compiler/source/product hashes, LLVM, disassembly, exact commands and timings are
retained below the external `build/tests/numerical-optimization-11/` area.
The optimizer ablations retain binary-identical neutral results for A89/A91/A95
and favorable allocation/instruction changes for A93/A94. Current source,
commands and product identities are conserved in the final evidence.

The independent C adapter generates deterministic sample input and expected
results. Astra implements the algorithms, storage, masks, filters, matrix and
complex operations. Public libraries are explicitly selected source modules;
only FIR selects owned coefficient/history allocation. Source conversion of
the C PCM `int` adapter is checked explicitly; no C i16 ABI was added.
