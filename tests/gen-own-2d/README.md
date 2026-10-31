# One named generic owner local

Run `sh tests/gen-own-2d/verify.sh focused` or `regressions` from the real
repository. The recipe checks the shared external build's source identity and
debug, werror=true, b_pch=false, linux_async=false options, disables ccache and
compiles serially. All generated outputs stay outside the source tree. The
regression mode composes the existing Q11A–D and selected Resource, copy-generics,
Q08/Q10B, object, virtual-async and lazy fences; it does not run the full registry,
LAZY Q4, CAD or real Linux/liburing qualification.

The user approved [Q11E option A and five exact historical replacements](../../docs/gen-own-2d-owner-local-design.md)
before semantic changes: one explicitly typed owned T local from the exact
incoming owner in a synchronous nonthrowing scalar/void generic helper. Resource
and exact heap/caller-backed Class instances share source spelling and preserve
different static cleanup contracts. A completed loan and one optional direct
terminal consuming site retain the same pointer/handle. Scope and early returns
clean the remaining owner once. No additional owner/Class storage, local owned
result, rearm, generic construction, result chain, loop/recursive ownership,
generic member/aggregate, adapter or async/throwing extension is included.

Eleven programs cover both same-T Class request/declaration orders, retained and
terminal paths, early returns before/after acquisition, a conditionally entered
local scope, nested scope retirement, empty/no-deinit and exact derived Classes,
Q08 child destruction, nullable incoming owners in all three domains, copied int/bool/u16/f32/f64
neighbors/results and exact Resource handles. Every program executes ordinary
native and independently verified opt/llc O2 code. Eight Class witnesses also
use separately compiled C entry/constructor/helper/loan observations under O0
and O2, comparing actual original pointer identities and allocation domains.
The allocator observer checks exactly one matching free, separately from the
standard-allocator unsuppressed Valgrind variants. Fatal traps gain no unwind
promise and are not successful-cleanup witnesses.

The TAP contract executable mutates Checked source/origin metadata, symbolic
Core source/type/acquisition/copy/producer shape, concrete cleanup/domain,
CFG transfer placement/duplication, independent SSA pointer/acquisition/move/
cleanup graphs in Resource and both Class domains, and native Class/heap plans.
Every mutation must reject and the restored graph must reverify. The source
negative driver checks deterministic diagnostics, exit 1, empty stdout and no
executable through nine public routes. The historical Q11D local-return case
is unchanged; the five separately approved older single-local negatives now
retain second-local rejection coverage.

Fault controls omit actual frees under the standard allocator and require
unsuppressed Valgrind leak detection. A separate allocator observer rejects a
duplicate free before a second unsafe host free. The intact positive is rebuilt
and rerun afterwards. Missing tools fail these gates explicitly rather than
counting them as passed.

See [ADR 0098](../../docs/decisions/0098-one-generic-owner-local.md) and
measured results. The task's pre-authorization
runner in `tools/design/gen-own-2d/baseline.py` records the old pinned rejection
boundary; its receipts are historical baseline evidence, not a post-change test.
Q11 remains OPEN; application-facing collection/member/text requirements need a
separately pinned milestone.
