# INDEXPATH-18 engineering record

The authorized base is `9286190fdc3650f127b8f523cbcfe052d41cb730`, tree
`00628c897e62c1baa9198da1cb6374b6171e10c0`. The native submission is SHA-256
`d69ce4e847a53fe9f24d4499a78ac02776d72b6f2d264d23fcf160eaf163a76e`.
The complete predecessor report remains immutable in the task runtime under
`indexpath18/predecessor-report.zip`, SHA-256
`b201bdf8421aadf537f08092c8111cd47f76b494d2dfc829b400d7199d0669c8`.

## Observed cause

All four frozen source cohorts reproduced the predecessor stop at
`compiler/cfg/consume.astra` bytes 650..664. The live source hash is
`f0e32ad005bc4a2d10244821bb84ab815c4aab7332654002066cd470382033c0`.
This is the array-index subexpression of `d.functions[f].entry`.

Private Class methods are elaborated as concrete bodies even when their source
declaration has no type parameters. The specialization syntax copier and its
separate structural consumer omitted `IndexExpressionSyntax`. Their explicit
fallback emitted the observed diagnostic while copying `CfgWalk.inspect`.
The first revised frozen-cohort execution moved that copy stop to `stack[0]`
at bytes 708..716, with the same 8,003 original typed observations. This exposed
the parser's distinct `VectorExtractExpressionSyntax` form for a constant index.
Both forms belong to the existing index hierarchy; true vector semantics are
not newly admitted. The new consumer checks the constant form's redundant
container/vector, index-token/literal and closing-token identities.

Core also lacked an indexed-value operation, and its existing field loads
required an authoritative static Place. Accepting the syntax alone therefore
could not qualify the requested operation.

## Bounded representation

The private storage profile adds Core kinds 19 (copy an indexed value), 30
(project a detached record value), 31 (store a plain copied element), and 32
(check bounds and return the evaluated integer index before the RHS). Kind 32
returns an ordinary integer and carries no storage authority. The store has a
separately verified source-bound buffer Place and must reference the exact
matching kind-32 child. It cannot use a snapshot as a writable address.

Only signed 32-bit index channels, qualified arrays of scalar/plain record
values, static receiver places and bounded effect-free index/RHS expressions
are admitted. Record snapshots own no alias or loan. Static owner validity and
field initialization remain Flow obligations; borrowed call lifetimes and
ordinary conditional cleanup retain their existing independent verifiers.
Nested record projections preserve exact field and nominal identities.

LLVM loads the array descriptor, checks the index with unsigned `>= count`
(also rejecting negative signed indexes), traps before accessing an element,
and uses the concrete element LLVM type for GEP stride. A store's guard occurs
before its RHS evaluation. No inbounds, noalias or nonnull promise is inferred.
The independent physical checker reconstructs descriptor source, element type,
index operand, guard/trap successors, field ordinal, load/store type and
alignment. LLVM layout caches retain their existing module ownership.

## Executed original-operation witness

The complete original `CfgWalk` declaration has a byte-preserving declaration
view whose C0 AST equals the declaration in the full original source. C0 builds
and executes it at both profiles. Its current native Core and CFG pass; SSA
construction exhausts the unchanged 8,000,000-step limit. This remains an
explicit resource deferral, alongside the prior three-specialization deferral.

The qualified native witness therefore uses the submission's permitted exact
operation view. The twenty original bytes `d.functions[f].entry` retain their
650..670 span (the index subexpression is 650..664). C0 independently confirms
that the parsed operation equals the operation in the full original source.
The separate wrapper and finite CFG driver are disclosed in `operation.py`.
The driver traverses a two-block cycle and observes reachable=2, edges=2 and
backedges=1, returning 25. Both O0 and O2 execute independent C0 and Astra-written
native ELF outputs with those values and clean unsuppressed normal-exit Valgrind
observations. The original operation's LLVM function remains present in both
objects. This witnesses the source operation, not the complete consumer body or
original CfgData shared identity and unrelated fields.

## Qualification

Both profiles retain all 106 inherited source/native program identities and add
15 distinct new programs with 15 distinct new ELF byte identities per profile:
121 program identities total. All 80 source statuses remain 56 admitted,
12 rejected and 12 deferred. All 1,044 historical proof stdout files, their
original commands and original source/tool/flag products are preserved; those
old proofs are not claimed as fresh evidence of changed code.

Each profile passes 25 new mutation categories with valid/restored twins:
17 source/model/CFG/SSA categories and eight LLVM-valid physical mutants.
They cover result TypeId, wrong array owner, source ID/span, field identity,
value/Place and owner flags, missing bound, evaluation order, cleanup,
specialization state/arguments, CFG/SSA correspondence and loan endpoints.
Physical mutations change GEP index/stride, alignment, bound count/index,
projection source, stored value and trap successor. Rejected output writes
preserve a real valid object and its linked executable. Existing Class/text,
Typecore/Flow/Core/CFG/SSA/LLVM ABI, numerical-defer and module layout-cache
lifetime gates also pass at both profiles.

Four frozen populations retain exact source/content/node/span identities:

| Cohort | Files | Nodes | Typed before/after |
|---|---:|---:|---:|
| Original | 79 | 174,297 | 8,003 / 8,003 |
| LLVM23-base | 85 | 188,293 | 8,297 / 8,297 |
| Class15-current | 92 | 206,465 | 8,760 / 8,760 |
| Previous live-initial | 92 | 208,328 | 8,810 / 8,810 |

All four move their source-copy stop to `swap(this.events, grown)` in
`compiler/semantic/flow-model.astra`, bytes 3589..3614. The typed counts do not
increase. The separate final-live population is not mixed into these cohorts.
Source-copy progression and the executed operation view do not qualify the
complete frozen compiler source.

## Measured costs

Final cold compiler builds used the frozen source-v5 recipe and LLVM 23.1.4:

| Profile | Wall seconds | Peak RSS KiB |
|---|---:|---:|
| O0 | 1,136.08 | 1,784,428 |
| O2 | 1,746.06 | 1,796,120 |

The builds overlap: their active union is 1,746.06 seconds. Executed final gate
commands have a 456.55-second active union over a 971.60-second span. They overlap
final builds by 259.16 seconds; the combined active union is 1,943.45 seconds.
Exact warm reuse is separately verified. Failed/superseded development attempts,
including their actual intervals, remain in the runtime evidence. Full session
elapsed includes investigation and packaging and is not the sum of these rows.

## Remaining limits

Indexed field assignment, effectful indexes, general borrowed-element escape,
move-only element extraction, foreign arrays and wider index channels remain
outside this bounded implementation. C0 admits some of these forms; native
refusal is reported separately from C0 rejection. The original complete
Utf8Message factory/exceptions/text_split, both named SSA work-bound cases,
wide-u64-to-f32 Valgrind discrepancy, whole-source safety and Stage 1 remain
separate unqualified issues. Fatal bounds traps carry no unwind or normal-exit
memory-cleanliness claim.

The installed native publisher supplies the final commit/tree and complete
source-bound changed-file patch. Its canonical report, rather than this durable
engineering record, establishes publication identity.
