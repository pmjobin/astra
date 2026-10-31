# CONTAINER-1A qualification

Run `tests/container-1a/verify.sh focused` for the three new registrations, or
`tests/container-1a/verify.sh regressions` for those plus the 21 selected existing
registrations and the fresh numeric/Q08/Q19A baseline witnesses. The script
checks source routing and debug/werror/no-PCH/no-linux-async options before
reusing the external build. It honors `PM_CODEX_BUILD_DIR` and
`PM_CODEX_RUNTIME_DIR`; outputs must be outside the source checkout.

- `contracts.vala`: seven TAP groups covering independent model retirement and
  corrupt/restore/reverify controls at Checked/Core, CFG, SSA, Native and actual
  LLVM. Corrupted LLVM is never executed.
- `execute.py`: all seven dumps; ordinary native and independently emitted
  `opt -passes=default<O2>` / `llc -O2`; exact output and identity/cleanup parity;
  separate unsuppressed standard-allocator Valgrind. Includes the public app,
  smoke owner, unrelated Utf8Message element, numeric spelling compatibility
  and a generated checked-error-after-growth witness.
- `observer.c`: test-only allocation IDs and hooks on the actual emitted
  owner-slot helpers/constructors/destructors. Checks backing transfer/clear,
  stable object and snapshot identities, reverse element cleanup, nested child
  cleanup and no surviving allocations on ordinary exits. Instrumentation is
  applied only after authentic compiler verification and is separately passed
  through LLVM verification/O2. No observer registry enters compiler output.
- `negative.py`: one minimal source per distinct refusal, expected parse versus
  semantic/CFG phase, later-stage refusal, no executable emission; six separately
  labeled fatal preconditions executed in native and O2 children.

Each Python runner uses a fresh external run directory and writes every command,
exit/stdout/stderr and identity JSON. Fatal growth injection deliberately proves
no ordinary commit or cleanup callback before the trap; it makes no recovery,
unwind or leak-free claim. No historical negative fixture is edited.

See validation,
[ADR 0100](../../docs/decisions/0100-indexed-heap-owner-slots.md), and the
[language guide](../../docs/language/owner-slots.md).
