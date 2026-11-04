# CLASSSTORAGE-15 qualification on LLVM 23

The bounded private Class storage/owner implementation passes its engineering
qualification at O0 and O2. Whole-source native admission remains deferred; no
Stage 1 claim follows. The canonical installed-workflow report records final
Git and publication identities. The earlier environment-blocked record in
`selfhost-classstorage-15.md` remains historical and unchanged.

## Provenance and source roles

The exact submission is `ASTRA-SELFHOST-CLASSSTORAGE-15-SUBMISSION.zip`, 22,880
bytes, SHA-256 `0a668794983c3222c0df3e3bdd195296f089489407f97ef34964c6b9ec8b656f`.
Its original base is `7b8fea49cdd3b3b8bb284d4299a12d31b01ba682`, tree
`529159ff7c48808cf19d278c4015ad1a63adcaf4`. The GENERICS-14 predecessor report
has SHA-256 `0c0df4ce1eaae92526b3a8427be0875f6687f2ef9d567a715bab414bf7b3fbf0`.

Continuation follows the user-authorized LLVM 23 migration at
`dfaffacea747640405af9afefe8e6c5833d0e8a0`, tree
`6b824f6611776c6578f0bf64d78b47a8ed7c0ca3`. The previously published checkpoint
has report SHA-256 `4251e394e062d00193b487deeef49e2000b9f55e1487bb7454c2e823464b74b2`.
Installed intake resume refused an already-published intake; the documented
explicit amendment preserves that checkpoint. No reset, rebase, repinning or
installed-workflow patch was used.

Evidence below is relative to
`~/Workspace/codex/work/astra/runtime/classstorage15/resume-llvm23-v1/`;
products use `~/Workspace/codex/work/astra/build/classstorage15-llvm23-v1/`.
The current independent C0 oracle has SHA-256
`e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b`.
It compiles separate reference applications. The standalone Astra-written
emitter builds application LLVM itself; no C0/Vala application-body fallback is
used for claimed native products. C++ probes generate layout-only descriptions
from C0 syntax, without consuming candidate layout plans or application bodies.

The qualified implementation products retain exact source/recipe/tool identities
under `native-source-v8/`, `native-component-v4-O0/` and `native-component-v4-O2/`:

| Implementation | SHA-256 |
| --- | --- |
| O0 | `b2502fb71353f7ec2641ecd8026c51d197d22f4252df20fa482f9c6b26d817f9` |
| O2 | `48f8788e2b197ffe8f2e466a597e282bd04f9258ce3ab53eee16da6cbee130f3` |

## Qualified behavior and evidence

`compiler/backend/llvm/CLASS-STORAGE-ABI.md` specifies the opt-in x86-64 private
profile. Eight-byte Class handles have separate source-ordered payloads; owning
slots retain their actual descriptor addresses. Independent source/type-owner,
constructor/inventory, Core/CFG/SSA, ABI and LLVM graph consumers check the result.
Payload addresses are bound to the current source CFG operation, and caches
belong to one module/context. GENERICS-14 still has exactly one hidden borrowed
receiver. No public C/COM/GObject Class ABI or universal heap policy is added.

| Required gate | Actual O0/O2 result |
| --- | --- |
| Inherited native executions | All 52 original program identities per profile pass C0/ABI/LLVM/object/ELF/Valgrind replay. |
| New frozen positives | 19 per profile pass; at least 12 belong to the original preimplementation population. |
| Later runtime observers | Four additional controls per profile pass, with their later freeze phase explicit. |
| New substantive mutations | 17 model and 18 physical categories per profile reject with valid/restored twins. |
| New semantic refusals | Ten parser-valid C0 negatives per profile refuse emission and preserve destinations. |
| Original source statuses | All 80 retain 56 admitted, 12 invalid and 12 deferred outcomes. |
| Original proof observations | All 1,044 original exit/output identities match through six dedicated consumers. |
| Inherited mutations | Core 22, CFG 26, SSA 30, LLVM 21, ABI 17 plus numeric guard, and GENERICS-14 19 model/six physical categories retained. |

New cases cover fields, borrowed mutation, owner relay, normal/early/loop cleanup,
nested ownership, Bag transfer/replace/nominal separation, growth/order, negative
capacity, cross-source behavior, nullable transport, the real `Bag<FlowGraph>`
reduction and unchanged repository heap witnesses. Exact
`nonnull-result-origins.astra` and `prototypes/bag-take.astra` now pass complete
native baselines. Later observers add visible object identity, forced allocation
failure and null owned-child result/parameter teardown. They do not replace the
original frozen population. FlowGraph's independently measured payload is 288
bytes, alignment eight, with 32 fields; Bag and slot descriptors occupy 16 bytes,
alignment eight. Mixed bool/double/int fields occupy 24 bytes at offsets 0/8/16.

Receipts are in `native-corpus-v4-*`, `mutations-v4-*`, `negative-v4b-O0`,
`negative-v4-O2`, `inherited-native-v4-*`, `source-continuity-v4-*`,
`inherited-focused-v4/` and `final-proof-replay-v2/`. Physical mutants are resealed
before independent verification. `layout-lifetime-v1-*` exercises actual Class
emitter contexts with the inherited guard, a deterministic retained-cache fault
and restored controls. All normal qualified executions have unsuppressed memory
receipts. Default allocation exhaustion matches C0's SIGILL before transfer or
publication (`failure-v4-*`); fatal-exit leak observations remain visible and are
not normal-exit memory-clean claims. Null ownership is distinct from moved state.
Literal-null owned-child transfer is refused, while null owned results and moved
parameters are legal. The separate null-field proposal is C0-admitted but traps
at runtime; it is not misclassified as a semantic negative.

## Compiler-source frontier

| Identical input population | Parsed nodes | Before typed observations | After |
| --- | ---: | ---: | ---: |
| Original 79 inputs | 174,297 | 1,333 | 1,651 |
| LLVM 23 base, 85 inputs | 188,293 | 1,370 | 1,705 |

Node/kind/span/source-hash identities remain exact, including generated
Utf8MessageFactory backing. The current population has 92 inputs, 206,465 nodes
and 1,861 typed observations; its actual C0 parse/check passes. Every native
ledger advances beyond the real Bag constraint and stops at
`lib/astra/collections/vector.astra`, span 140..1018:
`DEFERRED: generic Class requires the bounded empty receiver policy`.
Typed observations are not whole-program Flow/IR/LLVM admission; unvisited nodes
retain their disposition. Final observations use `ledger-after-*-v2/`.

## Costs, continuity and limits

Cold final emitter O0 took 16:19.14, peak RSS 1,712,384 KiB; O2 took 25:32.17,
peak RSS 1,661,244 KiB. Exact warm reuse took 1.31 s and 1.10 s. Separate raw
GNU-time/command receipts retain compilation, oracle, query, execution and test
costs, including failed attempts. Earlier GEN14 costs describe different workloads.
The guarded touched-source format pass changed no bytes; full read-only checking
passed all 4,687 sources. All 451 protected files, five excluded Windows scripts,
6,622 donor identities, local configuration/hooks and installed skill are preserved.

Raw development failures remain distinct: declaration gate, mixed-origin
acceptance, missing Class comparison, allocator-failure policy, C0 parameter rule
and type/Flow helper dependency were corrected. A combined-CLI proof attempt
failed at its first compatibility query; the unchanged six-consumer replay then
passed all 1,044 observations. Early allocator-interposition experiments are
separate from final predecessor-style linker-wrapper qualification. Old products
retain their old source/recipe identities and are never repinned.

The wide-u64-to-f32 Valgrind numerical discrepancy remains DEFERRED, with the
original receipt and current O0 reproductions. Memory cleanliness or successful
optimized observations do not resolve it. Remaining profile deferrals include
Vector-style generic Class storage, caller-backed `.init`, Class-field buffer
indexing, owning-Class record projection, general owner-field rearm, custom
allocation/destruction, partial-construction rollback, shared/weak ownership,
inheritance/virtuals and public Class ABI. No full registry, release, public push,
donor mutation, mass reformat or Stage 1 claim is made.
