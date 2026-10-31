# Owned state campaign: prototype and authority map

Historical Surge-6 record. The separate completion successor
qualifies later changes without altering this result.

Intake base `de68b7afe514a02e97d821d14b612190218b497d`, tree
`591ac56a5709e20bbb16fc8d192ce84b75ccbd1b`. The first four source prototypes
were tried with the pinned compiler before compiler edits. Their actual refusals
were property ownership qualifiers, Class-owned struct fields, unknown Bag.take,
and an arena library evaluation-order error (fixed by finishing lookup before
borrowing the field). The native arena prototype then ran successfully.

| Stream | Existing authority and gap | Selected representation and proof |
| --- | --- | --- |
| S1 | Copied lazy state machine; borrowed getter must project one owned field. `prototypes/owning-lazy.astra` is refused. | Explicit composition witness: separate copied lazy `ready` property, private owning `Utf8Message` field and bounded `content` property. This is useful current-source evidence, **not** owning-result lazy syntax or a checked borrowed accessor. Full S1 remains unresolved. |
| S2 | One Resource field is also the record's scalar cleanup token at Core/CFG/SSA. `nested-resource-event.astra` and `record-batch-rollback.astra` are refused before lowering. | Multi-owner records need a field-by-field initialized-prefix and cleanup authority, including null first children. Merely lifting the field-count checks would lose later children or double-retire moved state. No such relaxation is made. S2 remains unresolved. |
| S3 | Default heap/buffer backing uses fatal allocation; existing private fields, checked errors and borrowed receivers suffice for a separate storage policy. | Explicit `ByteArena`: receiver owns byte backing and metadata; checked aligned-offset bump admission; LIFO release; monotonically increasing receiver-relative IDs; checked scalar reads/writes. No pointers or storage loans leave the arena. Backing allocation remains the existing fatal policy. |
| S4 | Exact-Class Bag previously had reserve/append/count/capacity and immediate inspection. | Native stable-order `take(index)` into one fresh heap owner, and consuming `replace(index, move owner)`. New Checked/Core/CFG/SSA nodes/events; exact template and native ABI recipes; retained LLVM bounds/shift/clear/destructor correspondence. Existing layout and methods preserved. |

New S3 and S4 API is additive. No unique/shared lifetime, existing allocation
failure behavior, C POD ABI, async provider storage, or public output contract is
reinterpreted. Source input, stage mutation, public O0/O1/O2, observed cleanup,
and memory evidence are recorded by `tests/owned-state-6`.

The source composition does not discharge historical LAZY-1 Q4, which remains
HELD/INCOMPLETE. Eight authored application entrypoints do not imply eight
executed applications: A43/A44 are retained refused prototypes. The campaign
cannot receive PASS without the missing S1/S2 mechanisms and application gates.
