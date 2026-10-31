> Historical donor documentation, preserved for design and usage context. Private host paths are omitted; original bytes and qualification receipts remain in the verified donor archive. This is not current foundation qualification.

# Surge 10 integrated applications

These are distinct public Astra programs, with real runtime inputs and independent
output/ownership oracles in `tests/language-generalization-10/apps.py`. The
campaign requires all twelve A73–A84. Each has individual component evidence;
the final integrated qualification is recorded in the campaign validation.

| ID | Source / behavior | Qualified composition | Current evidence |
| --- | --- | --- | --- |
| A73 | `a73-document.astra`: parse `id/name/id/name`, construct a nested document, return its selected owning leaf and retire the rest | G1 nested Resource/Class/buffer values, full transport and prefix rollback; G2/G6 owned text splitting; earlier UTF-8, process arguments and C ABI | O0/O1/O2, 125 commands, unsuppressed Valgrind; checked failures before each field and after complete construction; alias/copy refusals |
| A74 | `a74-router.astra`: process `L:id`, `T:text`, `P:id`, `emit`, `empty`, `fail` commands separated by `\|` | G1 owned Resource/text/record alternatives and active-case replacement; G2/G6 owned command collection; earlier checked errors and native execution | O0/O1/O2, 68 commands, unsuppressed Valgrind; repeated keys retain independent allocations; failed switch preserves pending owner; numeric discriminator and owner copy refuse |
| A75 | `a75-archive.astra`: parse distinct CSV keys, archive copied stamps, unique assets and move-only packets, then grow/replace/extract | G1 owning packets; G2 one general abstraction and copied-U method; G3 copied/borrowed iteration; G4 computed template properties; earlier C Resources and UTF-8 snapshots | O0/O1/O2, 62 commands, unsuppressed Valgrind; high keys and independent order/value/destructor oracle; aggregate copy and relocation during a loan refuse |
| A76 | `a76-pipeline.astra`: stateful recurrence generator, filtering, resumable traversal and nested summaries | G3 stateful/fixed/slice/general collection iteration; G2 copied records; earlier checked errors and Resource lifetime | 68 commands; zero/break/continue/failure/tail cases; owner death and escaped view refuse |
| A77 | `a77-analyzer.astra`: build, split, parse and scalar-slice runtime Unicode text | G6 byte/scalar distinction and unchanged snapshot after malformed suffix; G1 enum/owning report; G2 token collection; earlier UTF-8 and checked parsing | 74 commands; counted NUL, four-byte scalars, strict integer bounds and malformed encoding; record copy/private backing refuse |
| A78 | `a78-cache.astra`: two memoized derived summary sources with input-dependent packet caches | G4 dynamic property dispatch, owned generic cache, failed first attempt/retry and identity; G1 Resource/text/buffer packets; earlier virtual Classes | 56 commands; exact attempt counts, payload identities and teardown; cache copy/move refuse |
| A79 | `a79-jobs.astra`: prepare/retry data jobs, complete, fail and cancel/join a child | G4 checked owning cache retained through real cooperative delay; G1/G2 chunk storage; earlier VirtualExecutor | 44 commands; actual completion/error/cancellation trace and frame retirement; suspended generic loan refuses |
| A80 | `a80-null-workflow.astra`: optional row store, action/callable dispatch and ticket weak acquisition | G5 generic/interface/Fn contracts, short circuit and field invalidation; G2 copied rows/G3 traversal; earlier Shared/Weak | 56 commands; present/absent/empty, live upgrade and expiration; null promise/stale property proof refuse |
| A81 | `a81-inspector.astra`, `a81-model.astra`, `a81-minimal.astra`: runtime selected schema member inspection | G6 opt-in Class/record/interface descriptors and same-model registry-free peer; G1 owning session transport; earlier native interfaces/text | 84 commands; independently computed nominal IDs/ordinals/read/call values, unknown/forged ID checks; private/wrong typed receiver refuse |
| A82 | `a82-provider.astra`, `a82-repository.astra`: independently compiled inventory repository and consuming transaction receipts | G7 nested owning record and closed repository unit exports; G1/G2 storage/growth/replacement; earlier native modules | 87 commands; five independent link combinations, runtime transaction oracles and unsuppressed Valgrind; wrong ABI/module/target, copy/private/specialization refuse |
| A83 | `a83-diagnostics.astra`: read a real file and aggregate tagged diagnostics into formatted output | G1 owned events/records, G2 owning archive, G3 copied summary iteration, G4 computed metadata, G6 Unicode; earlier POSIX files and decimal formatting | 75 commands; byte-exact reports, NUL/malformed/truncated text, parse and missing-file errors; owner copy/private file storage refuse |
| A84 | `a84-stream.astra`: typed arena packets, recurrence, saturating lanes and encoded-byte checksum | G1 nested Resource/arena records, G2/G3 copied sample collection/iteration; earlier ByteArena and strict u32 saturation | 71 commands; capacity/range/parse rollback, alignment/expired guards and deliberate runtime guard mutant; private storage/implicit numeric conversion refuse |

The shared `resources.c` adapter performs genuine independent C allocations,
checks nominal destructor domains and exact live allocation pointers, and emits
observations. Logical keys may repeat across independent allocations; each of
the 256 live registry slots tracks one actual pointer. Lookups validate membership
before reading an object, and only the owning cleanup frees it.
All parsing, data structures, routing and arithmetic are Astra. `resources.vapi`
is the explicit foreign boundary. Hosted argument/text/byte adapters are the
existing library providers. A79 explicitly links the cooperative executor object;
A83 explicitly selects the POSIX file provider. No regex or JIT is selected.

Run the registered public recipes in the coordinator's existing strict build:

```sh
CCACHE_DISABLE=1 PYTHONDONTWRITEBYTECODE=1 meson test -C <historical-private-path> --no-rebuild --num-processes 2 --print-errorlogs 'language-generalization-10-application-*'
```

Each recipe compiles strict C adapters and the real source at O0/O1/O2, checks all
public typed stages, executes input-dependent value/retirement oracles and runs
every success and checked-failure case under unsuppressed Valgrind. Receipts
record exact compiler/source/product hashes and commands beneath the external
build's `tests/language-generalization-10/applications/` directory. Generated
invalid sources are task-only build products. Source, portable recipes and
concise findings remain in Git.
