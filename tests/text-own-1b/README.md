# TEXT-OWN-1B qualification

Run `sh tests/text-own-1b/verify.sh focused` from the repository root. Set
`PM_CODEX_BUILD_DIR` and `PM_CODEX_RUNTIME_DIR` to external project paths; the
recipe verifies Meson source routing and uses the existing debug/Werror,
PCH-disabled, Linux-async-disabled serial configuration. `regressions` also
runs the existing focused GEN-MEMBER/CONTAINER/Q19A/generic/ownership/error
selection and the four buffer-exchange verifier registrations plus source tests.
It does not run the full registry, CAD, strict LAZY or live liburing.

- `privacy-model.astra` is an unrelated Class with private scalar, owned byte
  buffer and readonly snapshot fields. `privacy.astra` tests authorized same-Class
  other-instance access, accessors/lifecycle, unmarked fields, inherited base
  methods and ordinary identifier uses of `private` across files.
- `contracts.vala` injects/restores actual unauthorized same-type field accesses
  in Checked/Core/CFG/SSA, native field/caller/inventory faults, and actual LLVM
  field index, lexical-function placement and allocation-extent faults. It
  verifies stage independence after retiring predecessor graphs. Corrupted IR
  is never executed.
- `negative.py` checks actual first refusals, later-stage refusal and absence of
  an executable for external field reads/writes/indexing/borrows/replacement/swap,
  same-file/other-Class/derived-Class access, initializer bypass, builder access,
  slice escape, self-alias and unsupported visibility placements. Existing
  historical fixtures remain unchanged.
- `execute.py` compiles/runs real Astra native programs and independent
  `opt -passes=default<O2>` / `llc -O2` artifacts, with exact byte stdout/stderr
  and exit oracles and unsuppressed Valgrind. It covers empty, ASCII, composed/
  combining/four-byte/scalar-boundary/NUL text, fragments splitting a scalar,
  incomplete validation followed by successful retry, malformed repeated errors,
  growth/reserve, snapshots, input retirement, owner moves and Bag integration.
- `observer.c` includes the unchanged Q19A test observer, interposes real
  allocation/free only in test binaries, and observes complete builder layout,
  grow/append/snapshot/cleanup events. It checks exact extents, copied input,
  allocation independence, stable payload bytes, release of prior growth
  backing and eventual exactly-once retirement. Native/O2 normalized traces must
  agree; ordinary binaries acquire no instrumentation dependency.
- `limit-observer.c` seeds a deliberately impossible near-I32-limit count through
  test-only C callbacks, observes the actual append rejection/no-op without a
  write or allocation, and restores the real empty state before cleanup. A
  separate fatal child observes the exact INT32_MAX growth request and denies it
  before any large allocation. These are hostile-state guard controls, not valid
  huge-buffer programs or a foreign ingress API. No corrupted verifier artifact
  is executed, and no fatal-path unwind guarantee is claimed.

Every run retains its generated source, stage dumps, LLVM, executables and
per-command evidence under a fresh directory in the external build tree. Earlier
failed attempts are preserved. See the milestone validation document for actual
delivered counts, identities, limitations and protected-user-file comparison.
