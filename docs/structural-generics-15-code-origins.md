# Scoped callback inspection and nonconsuming lookup

Map now provides a generic copied-result lookup that observes an indexed entry
through an exact typed callback. Cache composes that lookup and records hits and
misses. The exercised owning-record payload retains its Resource and buffer
through repeated reads, Cache removal transfers the complete entry, and every
resource retires exactly once.

Source, Core, CFG and SSA reconstruct callback code targets from their own
addresses, parameters, locals, fields and calls. SSA also follows physical block
edges and record leaves. Indirect calls add argument-flow equations until the
graph stops changing. An incomplete candidate set may add conservative equations;
only a complete, grounded set can justify acceptance. Each actual target then
passes the existing scoped inspection effect checker. A borrowed signature by
itself supplies no read-only promise.

Code storage exposed through opaque pointer/Class/callback boundaries becomes
unknown. Native module production separately refuses callback-dependent scoped
loans until the interface can express and check their required effects. This is
unfinished native-contract work, not an accepted language restriction. The
registered unit control verifies the diagnostic and absence of both output
object and interface. No producer algorithm is serialized as a workaround.

Compiler `84b6c3b42e99d9279557b843746d07f6f93c67be8adfb892004547e5d65e011a`
passed 109 structural source programs: 1,854 checks and 327 unsuppressed memory
runs. After adding Cache lookup, the five affected Map/Cache and callback
programs passed another 86 checks and 15 memory runs. The final native-unit
recipe passed 640 checks and 141 memory runs; all 198 negative cases passed
1,584 checks. All 194 structural proofs passed, including three mutations that
destroy the predecessor representation and insert a write in an actual callback
target. Core, CFG and SSA each reject the write through their own effect checker.

Exact recipes, source hashes, products and receipts are recorded in
`structural-generics-15-code-origins.json`. These are focused increment results;
the affected registry and final G7 have not been rerun for this compiler. No
historical negative expectation changed, and the pending fixture proposals remain
pending.

The first SSA build omitted its new source from the compiler's separately
assembled source list. A later build exposed Vala's definite-assignment rule for
the iteration counter. Both failures are retained in runtime build logs. The
external C-caller probes stopped at unsupported C-boundary syntax/type checks and
supply no callback-effect credit.

The code-field analysis currently unions nominal fields and formal parameters.
Additional instance/context precision and complete Source/Core traversal controls
remain G1/G6 work. This increment does not establish a complete generic/member
contract, native callback exports, the useful application, or milestone PASS.
