# GEN-MEMBER-1A finite qualification

Run `sh tests/gen-member-1a/verify.sh focused` or `regressions` from the real
repository. The recipe validates external source/build/options routing, uses
debug + Werror, disables PCH/ccache and Linux async for this bounded build, and
compiles serially. `PM_CODEX_BUILD_DIR` and `PM_CODEX_RUNTIME_DIR` select the
existing external work area. It does not alter project defaults.

The source contract is in [ADR 0101](../../docs/decisions/0101-exact-class-generic-bag.md)
and the [language guide](../../docs/language/generic-class-bags.md).
Every positive uses [one library Bag declaration](../../lib/astra/collections/bag.astra).
The original Q20A concrete example/tests remain intact.

- `gen-member-1a-contracts`: seven TAP groups build the authentic two-element-type
  application, retire prior stage graphs, mutate one authority at a time, require
  refusal and restore/reverify. Covers Checked definitions/keys/fields, Core
  member operation recipes/cleanup/init, CFG/SSA keys/query/disarm/cleanup and
  indexed loan/mutation exclusion, Native instance/member/borrow/capacity/element
  correspondence, and both actual LLVM helper bodies. LLVM corruption is never
  executed; same-signature cross-Class destruction/member swaps must fail the
  artifact's independent bindings.
- `gen-member-1a-native-execution`: native compiler output plus independent
  host-entry emission, `opt -passes=default<O2>`, verification, `llc -O2`, linking
  and execution. Exact stdout/stderr/exits are captured. Includes combined and
  individual Diagnostic/Utf8Message bags, source/request order, same-key
  coalescing, distinct definition keys, stable local owner moves, empty/1/2/3/
  early/checked-error paths and helper pay-for-use. Unsuppressed Valgrind runs
  the ordinary standard-allocator positives when installed.
- `gen-member-1a-source-refusals`: verifies the first rejecting phase and every
  later requested output, with no executable. The diagnostic comparison uses
  only actual error text, never fixture filenames. Distinguishes parser scope,
  semantic admission/type/borrow failures and CFG moved/released-owner failures.

`observer.c` is test-only. After authentic compiler verification, `execute.py`
adds observation calls to a separate emitted module. Independently compiled
O0/O2 observed binaries track real allocation IDs, two separate descriptors and
backings, exact element/child/snapshot pointers and bytes, old-carrier clearing,
2→3 replacement, no element retirement during reserve, reverse exact cleanup and
zero ordinary live allocations. It supplies no production collection behavior.
Its traces are separate from untouched standard-allocator memory checks.

Dynamic invalid index/full/null append and injected grow OOM run only as
expected fatal children, without memory/unwind claims. No known double free or
verifier-rejected LLVM is executed. Each invocation preserves a fresh `run-*`
directory under the external build's `tests/gen-member-1a/{execution,negative}`;
`current.json` identifies the completed run and `checks.json` retains commands,
expected/actual exits, stdout/stderr, source/artifact hashes and limitations.

The selected regression recipe replays Q20A/Q19A, Q11A–E, Q08/Q10B, numeric
buffer/slice/swap, checked errors, copyable generic structs/functions/capabilities
and generic values. It does not claim the full registry, strict LAZY, real
liburing, CAD or hardware/GUI qualification, or broader generic containers.
