> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# Concurrency and runtime applications A109–A120

These twelve checked-in native Astra sources execute at public O0/O1/O2.
Independent C observers check data, concurrent entry, kernel activity and exact
cleanup. C supplies observation and the explicit runtime/foreign boundaries;
the application owns native objects, tasks, mailbox messages and network buffers.

| ID | Source | Executed work |
| --- | --- | --- |
| A109 | `a109-image-tiles.astra` | Owned 512-pixel tile, independent checksum, atomic shared/weak race and one destruction |
| A110 | `a110-resource-registry.astra` | Two bounded polymorphic registry owners, shared interface identity, virtual values, owned child and weak expiry |
| A111 | `a111-boxed-snapshots.astra` | Ordinary and explicitly boxed Monitor snapshots containing owned record-buffer storage; four worker clones |
| A112 | `a112-monitored-ledger.astra` | Four contending writers, checked rejected credits and 7,528 accepted updates |
| A113 | `a113-guarded-transfer.astra` | One Monitor owns two unique accounts; four opposite-direction workers preserve both balances |
| A114 | `a114-singleton-configuration.astra` | Failed initialization/retry, racing publication, busy/quiescent shutdown and expired weak |
| A115 | `a115-callback-broker.astra` | Four exact contexts retained by C, real worker callbacks, caught native error and joined retirement |
| A116 | `a116-parallel-batch.astra` | Four migrated parallel batches, checked errors, cold/active cancellation and outstanding shutdown |
| A117 | `a117-framed-service.astra` | Astra TCP listener with four independent peers, fragmented binary frames, EOF/refused/busy endpoints and exact closes |
| A118 | `a118-udp-telemetry.astra` | Two real UDP producers, endpoint metadata, empty/max/truncated/delayed packets and cancellation |
| A119 | `a119-actor-worker.astra` | Four native producers, 512 FIFO owned messages through a bounded named mailbox |
| A120 | `a120-diagnostics-service.astra` | C callbacks, monitored shared Singleton, owned migrated service/result, TCP/UDP and quiescent teardown |

Run from the repository root, with products outside the source tree:

```sh
build=<historical-private-path>
python3 tests/concurrency-runtime-13/applications.py "$build/astrac" "$build/concurrency-runtime-13/applications"
```

The script records exact compiler/C/link commands and source/product hashes.
It asserts the complete twelve-ID inventory, checks O2 under unsuppressed
Valgrind, and instruments emitted Astra LLVM plus C with ASan/UBSan and TSan for
the new A109/A110/A111/A113/A120 compositions. The other mechanisms receive
sanitizer coverage in their dedicated tests. An optional trailing list such as
`A117 A120` runs a focused subset, identified as that subset in its receipt.
Some network/callback cases use public `-c` products and an explicit C main
calling the exported native entry, allowing independent linker observers.

Providers are explicit C11 objects and pthread link inputs, selected per case
in [applications.py](../../tests/concurrency-runtime-13/applications.py).
No system installation is required by the recipe. See the
[language guide](../../docs/language/concurrency.md) and
[qualification recipe](../../tests/concurrency-runtime-13/README.md).
A110 is a bounded registry rather than a new polymorphic container feature;
A111 uses the established owned buffer of records; A113 does not introduce a
general multi-monitor ordered-lock operation.
