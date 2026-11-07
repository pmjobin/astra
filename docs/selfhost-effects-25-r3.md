# EFFECTS-25-R3 source-bound revision

This is a completion revision of milestone 25. Original EFFECTS-25, R1, R2,
the preceding R2 amendment, and the delivered R2 report remain historical
**PARTIAL** checkpoints. This document records current engineering evidence;
the R3 campaign has not yet been published or qualified as complete.

The exact initial HEAD was `633b713cfc14de4d77166ea4220eb5a3bdb6f072`, tree
`952c6253e71742e1a60eb5e29f1d1c0c5913b57a`. Installed unchanged `pm-next`
accepted submission SHA-256
`9a053524e182be20dbb143af6f6bcf735470678c616048795da59e98e422b982`.
The predecessor's supplied filename was absent locally; the canonical ZIP
contained the exact required bytes, SHA-256
`e7b87031caf01b586df57d84b180685fa12001c2029979b67f1f19a38990c81f`.
Its 117 indexed payloads, 91 source snapshots, and reconstructed transport
(`ee0639032522c53b23fa9c33ab0dd90abcbed97e27b1a2319970152cb37b989f`,
42,224 logical files) independently verify. A byte-exact predecessor copy is
retained under `runtime/effects25-r3/predecessor-report.zip`.

The original E25-A-v1 native question and user answer were authenticated
against their session line hashes and timestamps, the R1 receipt, and original
approval record. Proposal SHA-256 remains
`d77c02f3144ab5dc3da41eb310b29cd02629b49876042934ea5071a1549ac66e`.
No duplicate approval was requested. No ABI or C0 policy expansion is authorized
by a passing small program.

## Independent baseline

Fresh O0/O2 execution retains 202 inherited non-effect source identities with
unchanged raw LLVM, plus all 60 R2 effect identities/profile: 35 actual error
paths and 25 success/cleanup cases, with 60 distinct effect ELF hashes/profile.
The inherited 39 semantic and 24 independently LLVM-valid physical categories
were rerun. All four frozen populations retain exact source/node/span identity
(79/85/92/92 files; 174297/188293/206465/208328 nodes). The 56/12/12 status
ledger and 1,044 historical proof hashes retain their original attribution.
The 451 protected paths, 6,622 donor files, installed workflow, hooks, LLVM
23.1.4, and 256-instance/8M-step limits were authenticated without alteration.

## Original constructor checkpoint

The unchanged declaration at `compiler/source/source.astra` bytes 134..220
has fragment SHA-256
`d899055a27a7f6906036b3551ce2e5837712a8285c0f05a8e102ed32fa2eab8c`.
Recoverable Flow now admits a zero-parameter, nonthrowing derived Error
initializer forwarding a text literal to a verified one-string base
initializer. The root's readonly snapshot/getter contract, exact nominal
ancestry, zero extra payload fields, and dynamic destructor chain remain
independently required. Production code contains no SourceBoundsError spelling
or file-specific exception.

The original base literal has no CheckedUse because its constructor was
deferred. A conditional Typecore fact establishes built-in string type only
for the literal identified by the actual initializer's lexical Binder scope,
zero parameters, exact base operand, and verified Error shape. CheckedIndex is
unchanged. Flow retains that original node as the message operand and checks
source call arity separately. Core/CFG/SSA/LLVM continue to verify owner,
handler, source and physical correspondence.

Thirteen new source identities execute through Astra at O0/O2: nine error and
four success/cleanup cases. They include exact/ancestor/sibling catch dispatch,
propagation, bare rethrow, replacement capture, throw-move, reservation abort,
loop error and ordinary owned-input retirement. C0 agrees; LLVM verification
and unsuppressed Valgrind pass. Independent GCC/Clang allocation observers see
the actual 32-byte derived payload, descriptor ancestry and distinct destructor,
nonnull throw origin, exact counted snapshot, snapshot-before-object cleanup,
and zero live allocations. Twenty new source-bound stage mutations and six new
LLVM-valid constructor alternatives are rejected per profile.

Focused component SHA-256:

- O0: `e870eab0c9b0661057ba82f077e2e86aa76da5cb0f3b3d5a970113d82366cd23`
- O2: `78f414c534ba942e80289bcebd60e623a20041974712ec3b8e2948befb7126d3`

Cold focused builds took 963.75 s / 1,330.53 s, peak RSS 1,495,280 /
1,487,768 KiB. Their workloads differ from the old combined compiler; no speedup
is claimed. Earlier syntax-check failure and two deliberately stopped builds
remain recorded. The stopped groups have measured command intervals but no
completed GNU-time CPU/RSS receipt; missing measurements are not inferred.

## Original function remains unqualified

The supplied witness defines `flow_number` in
`compiler/semantic/flow-query.astra`, bytes 1870..2001, SHA-256
`8641d4ff6a1f19cc8bfc0ccbec492a8f7d4248eebcb05373c15479e7114a3e68`.
It calls the real formatter in `lib/astra/text/scalar-format.astra`.
The full source witness remains unchanged. Independent C0 returns 42 and
passes returning-path Valgrind. Astra advances from `RECOVER_FLOW 3 6 0` to
`RECOVER_FLOW 3 778 0`: original `SourceBuffer`, bytes 2166..5373, fragment
SHA-256 `c5c1be3508f09f07250e89006b496d9e7742f015af9370d464c30bfc07b28e81`.

A separately disclosed dependency view retains byte-exact `SourceBoundsError`,
`source_append_text`, `append_int` and `flow_number`, and independently compares
their original C0 syntax subtrees. All exercised real Utf8ByteBuilder,
Utf8Message/error and hosted-byte dependencies remain. Unexercised declarations
are explicitly listed in the view receipt. C0 still returns 42; Astra reaches
real `Utf8ByteBuilder`, node 292, bytes 131..1520, fragment SHA-256
`62edc3969129ec25daca90f61f63042e8ebecb37dffc2738ca902d09e3f3a85f`.
There is **no Astra execution credit for flow_number** at this checkpoint.

## Independent owner-root investigation

Both fresh traces reproduce `CheckedIndex.add_signature`, graph 55 / symbol
2053 / predicate 26. Independent parsing finds no receiver slot, left capture
`this.signatures` with slot/root zero, and right local `grown` with slot six.
The verifier requires a proved field Place or a positive owned local slot.
Current evidence establishes neither authority for the left operand. It remains
**DEFERRED**; no root, slot, alias attribute or verifier exemption is invented.

C0 source probes also establish that a null checked receiver traps before a
later throwing argument. An owned call result passed directly to an owned
parameter is rejected: C0 requires an explicit move from an owner or null.
These facts constrain further admission. Fatal observations retain signal
attribution separately from GNU time's encoded exit status and receive no
returning-memory credit.

Remaining bounded receiver/generic/field/carrier obligations and original
native function execution still require implementation and qualification.
Minimum program and mutation counts do not close G3/G4/G5/G9 or establish Stage 1.

## Concrete-domain focused work

The second candidate adds concrete private method and free generic source
checks, preserving the original specialization maps and independent generic
consumer. The checked specialization policy requires a closed nominal Error
bound, private synchronous source, and an actual fieldless Class for a static
receiver. The consumer checks the copied declaration, precise error bound and
checked flag independently. The 256-instance limit is unchanged. Receiver
evaluation precedes a fatal null guard, which precedes all explicit arguments;
the receiver precedes success storage in the existing ABI plan.

Strict f32/f64 storage is admitted for scalar, copyable record and owned-buffer
carriers. The physical verifier checks source literal identity, operand order,
width, ordered comparisons, unordered inequality and absence of fast-math
permissions. Independent caller adapters compare exact NaN payload and signed
zero bits, mixed record fields, buffer length and unchanged poison on error.
These adapters receive no Astra-native source credit.

Inferred parentheses retain their child's ownership and pending facts. Typed
parenthesized Class construction remains C0-rejected. An owned buffer local may
receive an owned call result: evaluate/capture first, retire its old value only
on success, then publish and arm the replacement. The independent CFG consumer
reconstructs this order and the real slot; SSA checks its owner states and
unique result consumer. Self transfer commits the old reservation before
retirement, so the old slot is disarmed when the same owner returns.

The intermediate `domain5` O0 component genuinely executes 19 focused positive
source identities (floating carriers, inferred construction, Class call-result
return and buffer reassignment), with C0 agreement and unsuppressed Valgrind.
Its 24 independent FP bit/poison observations also pass. It exposed an older
blanket throwing-specialization gate and accidental C0-invalid Class local
rebinding. Neither is accepted as final qualification: the former now has a
bounded checked declaration policy and independent consumer; buffer-only
rebinding excludes the latter. Three C0 Class/Error rebinding negatives remain
explicit controls. The intermediate compiler's 110 repository input snapshots
match its recorded source hashes exactly, preserving both actual progress and
failures before the fixes. Final combined O0/O2 qualification remains required.
