# M18 B1 — transactional integer event journal

Requirements/reference/cost hypotheses selected **after** freeze commit
`f9f395eb4d467d10b95c871ea1492adc30f58c83`, on 2026-10-30 at
05:00:10 UTC. Freeze record SHA-256:
`944b759b829a58999ba2e515ad249ed3cf5fb41117c26fd25b01d9e3106d9e1e`.
Task-generated seed: **1666689098**. No B compiler measurement preceded this
selection. The freeze still records its original unselected state; this document
records the later choice without editing that history.

## Useful behavior and independence

Implement an atomic transaction journal in Astra. Persistent per-shard maps hold
versioned integer accounts. Transactions update several keys, perform reads or
tombstone keys, and either commit together or restore their entire initialized
prefix after a checked conflict. Subsequent transactions must see the restored
state. Produce every transaction's result and every final account state.

This is integer state reconciliation with persistent associative ownership,
checked rollback and retained history. It does not process PCM, FIR/biquads or
independent numerical windows. All decoding, state lookup/update, undo handling,
checksums and journal decisions belong in Astra. C supplies only bounded file
bytes/output storage, timers, allocation/lifetime/coverage observations and public
runtime edges. Python is an independent file generator and whole-dictionary
snapshot oracle; Astra must use per-record undo records rather than copying that
reference algorithm.

## Input and reference algorithm

Input is a sequence of 16-byte little-endian records, `<IBBHii>`:
transaction ID u32, shard u8, operation u8, key u16, expected version i32, value i32.
Transaction IDs start at zero and increase by one between contiguous groups;
all records in a group name one shard. There are four shards and 32 keys per shard.
An absent key starts `(version=0, value=0, present=false)`. Tombstones retain their
version. Group lengths vary among 1/2/3/7/17/31, with a shorter final group.
The application admits at most 8,193 records for this bounded example.

For each transaction, process records in order:

1. Key outside 0–31 causes checked code 2. A mismatching expected version causes
   code 3. Version matching precedes operation-specific checks.
2. Operation 0 adds value; operation 1 replaces it. Results outside
   -1,000,000…1,000,000 cause checked code 4. Both publish present=true and increment
   the version. Operation 2 tombstones the key, sets value=0 and increments its
   version. Operation 3 reads without changing state. Other operations cause code 5.
3. For each successful record accumulate
   `value_after * salt + version_after * 3 + (present_after ? 1 : 0)` in i64, where
   salt is 17 for even transaction IDs and 19 for odd IDs.
4. A checked error restores every prior mutation in that transaction, in reverse
   order, including repeated keys. Its checksum becomes zero and its first failing
   record index is reported. Successful transactions report code 0 and index -1.

The generator keeps four of each five transactions valid and deliberately injects
late version/key/range/operation faults in the other group. Its predictor is used
only to make varied inputs; the oracle independently reparses bytes and snapshots
the complete dictionary before evaluating each transaction. Empty input is valid.
Truncated input, nonconsecutive IDs, mixed-shard groups and invalid shard IDs must
refuse without publishing an output file.

Output starts with little-endian magic `0x4a4f5531` and transaction count. Each
transaction has `<iiiiq>`: ID, status, first error index, record count, checksum.
Then 128 sorted `<iiiii>` state rows contain shard, key, version, value, present.
C may serialize these supplied values but may not compute or reconcile them.

## Actual composition

- Use ordinary generic Map account ownership, a copied-record Vector undo log,
  and an owning history collection whose entries survive their transaction.
- Compile a real leaf/middle/consumer split. Opaque units provide typed metadata
  and property/helper behavior. Remove producer input copies before compiling the
  consumer and trace consumer access. No implementation-body fallback.
- Keep at least two independent local metadata candidates beside genuinely
  escaping history owners. Metadata/history destruction and selected checked
  cleanup remain observable. Include direct typed interface/property calls.
- Exercise a non-adjacent unused Shared clone through scalar helpers/branches,
  plus a weak-observed control that must retain lifetime operations.
- Provide sequential, four-shard threaded and actual io_uring+worker execution.
  Threaded runs use worker counts 1/2/4. Each job owns its context-backed input
  bytes and frame; state is private to its shard. The io_uring variant reads the
  complete file through public payload operations before submitting jobs; serial
  submissions are permitted and earn no overlap/pipeline scaling claim.
- Use distinct 2 MiB/64-slot input/job and 256 KiB/32-slot frame contexts. Verify
  final live/reserved payload zero, exact allocation/release conservation and
  retirement. Reserved backing, metadata and RSS remain separate measurements.

## Qualification and prospective cost hypotheses

Before measuring, the hypotheses are that independent metadata allocations and
the provably unused Shared clone can disappear at the same O2 pipeline, while
escaping history, weak observation, checked errors, map updates and every
destruction remain. Exact receiver/property calls may simplify where proved;
runtime-dependent choices must keep their behavior. No fixed speedup or exact
machine-size reduction is assumed. Neutral/slower timings stay in the evidence.

Compare facts on/off at O0/O1/O2 with the same input/oracle. Include original and
renamed/field-reordered/helper variants, local/native linkage controls, sizes
0/7/513/4093 and the upper admitted boundary, and seeds derived from the fixed seed.
Use exact full output bytes, actual heap/retain/code observations, repeated serial
timings, full-product unsuppressed memory checks and emitted ASan/UBSan/TSan with
explicit opaque/static dependency exclusions. Keep every failed attempt.

Only B source/oracle/test/registration files may change during this challenge.
Recheck the frozen production, binary and host hashes after each challenge run.
A necessary production repair invalidates B1: preserve it, repair generally,
requalify A, commit another freeze and choose a materially different challenge.
The original freeze and seed must never be rewritten to manufacture success.
