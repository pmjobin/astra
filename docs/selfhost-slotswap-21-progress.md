# SLOTSWAP-21: lexical receiver authority and owning record buffers

The frozen `CheckedIndex.add_signature` stop was a missing lexical receiver
authority. It was not a local-owner inference failure or a new record-element
policy requirement. The pre-repair observer records the actual field declaration
and its `owned CheckedSignature[]` type, but no resolved left operand symbol or
type. The right operand is an inferred local of that same canonical slice type,
flags `4`, classifier result `0`, and an independently verified value-record
element. All four original classifier results are exactly `2 0`.

`checked_this_type` previously depended on complete native Class eligibility for
ordinary methods. `CheckedIndex` has unrelated members outside that bounded
layout domain. This erased the receiver used by member selection even though the
field itself has a precise Binder declaration and declared type. The repair gives
an original nongeneric, direct instance method its exact lexical nominal receiver.
It excludes inherited and open generic declarations from this additional path.
It does not manufacture a receiver storage slot or a native layout. Existing
Flow admission, initialization, Core Place and independent Class layout checks
still qualify executable storage separately.

`CheckedSignature` contains `SymbolId`, two `TypeId` fields and two integers.
The ID records each contain one integer. The existing recursive element policy
already accepts this value-only shape and rejects ownership-bearing fields.
Independent C0 and C++ evidence measures a 20-byte, 4-byte-aligned element. The
unrelated `Parcel` witness has a nested ID, an `i64` and a boolean: 24 bytes with
8-byte alignment. Neither equal layout nor an erased pointer supplies nominal or
cleanup authority.

The existing end-to-end exchange representation remains the implementation:
ordered Core captures (kind 34), one closed exchange (33), corresponding CFG and
SSA operations, and independently verified LLVM descriptor snapshots. In this
Astra-written backend the descriptor is `{ptr, i32}`. Two complete aggregate
loads precede two complete opposite stores. The retained physical verifier checks
the exact storage addresses, types, order, guards and absence of intervening
effects. This is four aggregate memory instructions; the historical C0 description
of eight scalar instructions is not a description of this backend's output.
There is no allocator, element copy, cleanup, `noalias` premise or public ABI
change in the exchange. Existing dependent loan and cleanup responsibilities stay
with the declared slots. Aliased receivers and self-swap retain both captures.

The actual complete `add_signature` method is preserved byte-for-byte at
`[5784,6517)` in a disclosed whole-method view of the post-GENRESOURCE source.
Its independent C0 method AST matches the original. Other Class fields/methods
are blanked, and the bounded constructor, storage fields, exact nominal record
dependencies and capacity helper are disclosed by the corpus recipe. Its driver
checks the 15/16/17 boundary, 65 appends, repeated growth to capacity 128, every
row field and every symbol-to-signature ID. An allocation observer confirms
retirement of the old 16/32/64 capacities at growth scope exits, then reverse
field cleanup and one final Class cleanup. The observer implements no Astra
algorithm. This qualifies the view, not the complete original Class or compiler.

The four immutable source cohorts retain their exact population and node/span
digests. Their checked-use counts advance as follows:

| Cohort | Before | After | New facts in checked.astra after the old swap |
| --- | ---: | ---: | ---: |
| original | 14,966 | 52,257 | 362 |
| LLVM23-base | 15,593 | 54,255 | 379 |
| Class15-current | 17,637 | 59,268 | 384 |
| live-initial | 17,877 | 59,815 | 397 |

The next observed refusals are `conflicting or unavailable generic argument
inference`: `graph.slot_for(checked_target(...))` in the first two populations'
`flow-admission.astra` at `[3243,3351)`, and `graph.add(bad)` in the latter two
populations' `class-storage-flow.astra` at `[2690,2704)` and `[2820,2834)`.
These are source-bound observations, not a diagnosis or repair of that next
generic member-call boundary. Whole-source Flow safety and compiler execution
remain deferred.

Qualification recipes under `tests/selfhost-slotswap` retain the exact 159
inherited identities per profile. The current compiler freshly re-emits and
LLVM-verifies each input, compares raw LLVM byte-for-byte, and executes the
qualified retained ELF only when the source, product and toolchain identities
match. Object/ELF/C0/ABI qualification reuse is explicitly distinguished from
fresh checker and runtime execution. Thirteen new distinct programs per profile
exercise record ownership, generic specialization, aliases, empty buffers, return
paths, rearm, repeated growth and independent saved record values. New programs
have independent C0, C++ layout, LLVM, ELF and unsuppressed Valgrind evidence.
The final totals are 172 source identities/profile, with 172 distinct O0 ELF
byte identities and 152 distinct O2 ELF byte identities. The inherited O2
159-source/139-ELF distinction remains intact. Completed cold build commands
took 1178.691 seconds at O0 and 1820.557 seconds at O2. Their intervals overlap;
these durations are not summed or presented as an equal-work speed comparison.
Warm runs reuse exact input/product identities without rebuilding.

Adversarial evidence separates 14 retained record-authority mutations, ten
parse-valid source controls, and six LLVM-valid post-emission physical
alternatives. The four nested qualifier bit variants share one authority family;
they are not four independent verifier designs. Physical alternatives are checked
by external source/runtime/memory oracles, not attributed to the retained-module
verifier. The inherited 37 OWNEXCHANGE controls include the separate retained
physical audit; GENRESOURCE model controls and exact physical products retain
their own attribution. Every new authority mutation restores a valid twin.

Failed harness attempts are preserved: an initially non-owning assertion local,
an oversized short-circuit driver exhausting the fixed SSA budget, a parser-invalid
`readonly owned` fixture, and receipt readers that initially mishandled legacy
hash-only records or wrapper-encoded fatal signals. None is counted as a passing
semantic or normal-return memory test. The qualified driver retains the original
method and numerical ceilings. Source controls retain their actual first denying
authority; an earlier escape/domain refusal is not credited as a later loan proof.

The 256-instance and 8,000,000-step SSA ceilings, LLVM 23.1.4, public ABI, C0,
layout-cache lifetime, 451 protected files, read-only donor, 80 historical source
statuses and 1,044 historically attributed proof outputs remain separate
preservation obligations. Full compiler admission, the independent SSA stress
deferrals, Utf8Message factories/exceptions/text_split, wide-u64/f32 Valgrind
behavior, broader owner domains, Stage 1 and release remain unqualified.
