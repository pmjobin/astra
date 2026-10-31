# Owned-state application witnesses A41–A48

All eight sources execute at public O0/O1/O2 in the completion successor. The
qualification describes exact
outputs and memory evidence. This is a fresh eight-source slice, without a claim
that all historical 48 witnesses were rerun.

| ID | Source | Current evidence |
| --- | --- | --- |
| A41 | lazy-diagnostic-card.astra | One successful owned snapshot, repeated identity, separate receiver and moved receiver. Compiler-managed owning checked lazy with receiver-borrowed observations. |
| A42 | retryable-settings-reader.astra | Real invalid UTF-8 file, retry after correction, no warm I/O, separate receivers. Compiler-managed owning checked lazy. |
| A43 | nested-resource-event.astra | Two independent Resource fields, two live records, written-order initialization, whole move and null/live-field cleanup. |
| A44 | record-batch-rollback.astra | Checked second-owner failure, producer temporary retirement, initialized-prefix rollback, successful move and later full-record throw. |
| A45 | bounded-spool-allocator.astra | Selected byte arena, recoverable exhaustion, aligned offsets, release/retry and exact five-byte binary file. |
| A46 | scoped-buffer-index.astra | Byte-offset index of UTF-8/NUL data, checked index, LIFO and stale-ID failures, zeroed reuse. |
| A47 | diagnostic-queue-editor.astra | Bag<Diagnostic> growth, first/middle/last take, replacement, exact order/count/capacity, independent owner release and reused slot. |
| A48 | cached-diagnostic-rewriter.astra | Actual file bytes, empty/corrupt checked retry, independent message snapshots, mutable Bag<Utf8Message>, arena-built footer and byte-exact output. Uses the owning checked lazy property. |

`model.astra` supplies the actual owned Utf8Message lazy factories, diagnostics
and observers. `content` itself performs checked first-success access; no explicit
ready flag or source-owned cache field is required. Returned views are bounded
to exact borrowed consumers. Test C observes allocation/release and identity;
Astra and compiler lowering implement cache ownership, records, collections,
arena and file-processing logic.

Run the portable recipe in `tests/owned-state-6/README.md`. Select the model,
Bag, arena, Error, Utf8Message and existing hosted file/text sources explicitly;
link only the selected POSIX file/text/args providers and test observer. No new
runtime dependency is automatically linked.
