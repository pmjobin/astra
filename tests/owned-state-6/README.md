# Owned-state selected qualification

Run from the real repository with an external build directory:

```sh
export PM_CODEX_BUILD_DIR=${PM_CODEX_BUILD_DIR:-"$HOME/Workspace/codex/work/astra/build"}
export CCACHE_DISABLE=1 PYTHONDONTWRITEBYTECODE=1
meson setup --reconfigure "$PM_CODEX_BUILD_DIR" "$PWD"
meson compile -C "$PM_CODEX_BUILD_DIR" -j 4 astrac astra-owned-state-proof astra-args-llvm \
  astra-text-posix astra-args-posix astra-base-failure-trap astra-base-failure-hosted
meson test -C "$PM_CODEX_BUILD_DIR" --no-rebuild --num-processes 2 \
  --print-errorlogs owned-state-6-proof owned-state-6-runtime owned-state-6-refusals owned-state-6-sanitizers
```

Use `meson setup BUILD SOURCE -Dbuildtype=debug -Dwerror=true -Db_pch=false
-Dlinux_async=false` for a fresh build. Preserve existing source/output routing
and peer work. The default recipe needs LLVM 22, Vala, Meson, GCC/Clang and
Valgrind already available; it installs or downloads nothing.

The seventeen TAP registrations independently corrupt Checked heap origin, Core
acquisition/index, CFG acquisition/escape, SSA transfer events, exact native
member results and physical LLVM take/replace bodies. Additional record and
owning-lazy groups mutate ordered field obligations, checked rollback, factory/borrow
channels, cache destruction and physical gate state. Every model is verified
again after restoration. Verifier-corrupted generated programs are never
executed. The retained record
runner separately executes valid LLVM release-omission/doubling controls under
its observing host harness.

Runtime tests compile eight actual application sources using public O0/O1/O2,
record outputs and file bytes, and run each terminating scenario with
unsuppressed Valgrind. Arena edge tests include 0/1/odd extents, alignment padding,
I32_MAX requests, metadata exhaustion, failed admission without mutation,
stale IDs, LIFO refusal and zeroed reuse. Public `-c` plus GNU ELF allocator
wrappers independently measure physical backing versus logical admission and
final release. Test C only observes allocation and invokes the exported witness.

Refusal controls cover take/replace owner transfer, nominal mismatch, view escape,
mutation during inspection, moved/released owners, and private arena storage.
Four validly generated fatal index controls and both copied/owning lazy recursion
controls execute in child processes. A43/A44 now positively exercise independent
flat record owners and checked-prefix rollback. Three cache units cover checked
retry, warm identity, moves, inherited receiver slots, user destructor access,
unused caches, exceptions, early returns and constructor-free caller-backed
receivers. Class-owned/nested/generic record
storage and escaped cache views remain negative controls.

Detailed receipts and generated products stay in the supplied external build
area. Historical LAZY Q4 remains HELD/INCOMPLETE; neither the full 9k+ suite nor
CAD, GObject/GIR, SH-4, threading or self-hosting is implied.

The sanitizer test uses the refreshed retained executable LLVM emitter (including
its real hosted entry) to preserve reachable application code, marks functions
for ASan and runs LLVM's O2/ASan passes plus verification. Clang ASan/UBSan covers
selected C providers. This does not supply UBSan instrumentation for native Astra
arithmetic. Original program behavior is independently checked through the public
driver at all three optimization levels.
