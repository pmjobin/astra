# Finite generic heap Class forwarding

Run `sh tests/gen-own-2b/verify.sh focused` or `regressions` from the real
repository. `PM_CODEX_BUILD_DIR` defaults to the shared external Astra build;
the recipe verifies source routing, preserves its existing options, uses strict
serial compilation with ccache disabled, and keeps generated artifacts outside
Git. The regression recipe includes Q11B, Q11A, GEN-OWN-1, Q08/Q10B and their
selected Class/error/virtual-async/property fences. It is not a full registry run.

The user approved [Q11C's source and lifetime proof](../../docs/gen-own-2b-heap-forward-design.md)
before implementation and separately approved seven historical negative-case
replacements. One named exact heap native Class owner may enter a synchronous,
nonthrowing top-level native owned-T helper with concrete copied scalar neighbors
and a scalar/void result. Its body retains that owner or has one structural
forwarding site to another qualified generic helper. Conditional paths may
retain ownership. The owning transfer graph must end at a retaining sink;
recursive cycles, multiple sites and loop transfers are excluded structurally,
including dead code. Existing ownership flow handles actual move/use/loan state.
Heap generic owned results and owner locals remain deferred; Q11 stays OPEN.

Nineteen programs cover one/two/four-hop forwarding, same-T lexical/heap uses in
both discovery and module orders, inferred calls, one copied int/bool/u16/f32/f64
neighbor at a time, completed loans, conditional retention, scalar early return,
exact derived teardown, empty/no-deinit, Q08 owned child and legacy lexical
recursion. Each runs ordinary generated native code, independent opt/llc O2 and
a separately compiled C-client/O2 entry. Original Q11B Class fixtures and C
observer are shared through ordinary source inputs and a C include; they are
not copied or altered.

The C client instruments actual constructor, relay, sink and borrow entries.
Constructor pointers establish identity; every helper entry must receive that
same live original pointer and the separately planned allocation domain.
The independently compiled C entry bridge invokes the native main; no foreign
owning source API is introduced. Ordinary allocation observers interpose
calloc/free, call the real host allocator, verify exact destructor obligations
and reject freeing lexical storage or freeing a heap allocation twice. Source
and LLVM contracts check immutable instance domains, owner ordinal changes,
scalar result channels, no result candidate and no object memcpy/memmove.
Concrete generic heap transfers also require exact nominal source identity,
independently rejecting an injected subtype conversion after specialization.

Valgrind bypasses interposed allocator hooks. Separate OWN_MEMORY native/O2/
C-client companions therefore use normal host allocation and require zero
errors, zero live bytes/blocks and zero suppressions, with exact operation and
destructor traces. Their observer counts zero intercepted frees. Allocation/free
counts belong to the separate interposing executions. An omitted terminal free
in the two-hop program is detected by both observer and unsuppressed memory
companion. A duplicated free stops at observer exit 98 before a second unsafe
host deallocation; its memory-tool path is not executed. Two pre-invocation
traps return SIGILL without cleanup and qualify only the non-unwinding rule.

Seventeen independent mutate/reject/restore TAP controls exercise a forged source
owner, forged Checked eligibility/cycle, Core forwarded parameter/source,
missing acquisition and unreachable second site, concrete cycle/instance key/
lexical callee/subtype adaptation, CFG missing commit/moved read/double acquisition, SSA forwarded
domain/reconstructed cleanup origin/duplicate cleanup, and native origin
correspondence. The native physical verifier alone accepts the wrong origin
bit; the independent SSA correspondence validator must reject it. The contract
binary remains LLVM-free.

The negative driver pins deterministic diagnostics and exit 1, prohibits stdout,
internal failures and executable production, and covers six multi-source cycle
orders plus direct/mutual/dead cycles, unsupported callees, multiple sites,
loop transfers, heap results/locals, two owned formals, producer chaining,
aliases, nominal mismatch/upcasts, aggregate/member/foreign/throwing exclusions
and moved/loan/branch/loop state in explicit and inferred forms. Q11A/Q11B's
preserved fixtures supply the other existing exclusions. Only the seven approved
historical cases changed; their original behavior is positive Q11C evidence.

Full checks.json, abi.json, identity.json and per-program stage/LLVM artifacts
remain in the external build. The validation note
records final measured counts, identities, traces, retries and limits. No full
registry, LAZY Q4/CAD, real Linux/liburing, GUI/hardware, package/network or
generic heap-result qualification is included.
