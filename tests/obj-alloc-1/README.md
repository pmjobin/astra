# Allocated object ownership checks

Run from the real repository root with its external build directory. Respect
the active task's limits and coordinate reuse with linked worktrees. These commands need Meson/Ninja, Vala/GLib, LLVM 22 (`opt`, `llc`), a C
compiler and Valgrind; the allocator observers target the existing Linux/glibc
allocation profile.

```sh
export PM_CODEX_BUILD_DIR="$HOME/Workspace/codex/work/astra/build"
export PM_CODEX_RUNTIME_DIR="$HOME/Workspace/codex/work/astra/runtime"
export CCACHE_DISABLE=1
mkdir -p "$PM_CODEX_BUILD_DIR" "$PM_CODEX_RUNTIME_DIR"
meson setup "$PM_CODEX_BUILD_DIR" "$PWD"
meson compile -C "$PM_CODEX_BUILD_DIR" -j 1 astrac astra-obj-alloc-loans
meson test -C "$PM_CODEX_BUILD_DIR" --no-rebuild --print-errorlogs obj-alloc-1-loan-contracts obj-alloc-1-native-execution
```

The Python driver can also run directly with external outputs:

```sh
python3 tests/obj-alloc-1/execute.py "$PM_CODEX_BUILD_DIR/astrac" "$PM_CODEX_BUILD_DIR/tests/obj-alloc-1/execution"
```

`owned` observes allocation, constructor/destructor/free order, distinct equal
objects, stable addresses through owner moves and forwarding, lazy/computed
receivers, early return and deliberate release. `checked` distinguishes argument
failure before construction, failed owner results, abandoned named moves and
successful checked acquisition/release. `lexical` checks caller-provided result
storage without allocator references. `mixed` uses all three storage forms for
one class. `loans` exercises inherited readonly fields, copied views, branch/loop
joins, nested extents and independent snapshots. `nested` checks heap parameter
domain inference and successful moves inside conversions and class/record field
assignments, without another call seeding the domain. `empty` checks independently
allocated identities without user deinit.

Each fixture executes through `astrac`, then independent O2/LLVM verification,
object emission and C linkage. A test-only IR bridge observes the actual `probe`
receiver before optimization; it changes no owner or storage operation. A
separate C observer variant leaves the allocator visible to unsuppressed
Valgrind. Fatal allocation must trap before any constructor/destructor event.
Negative source forms must report the declared diagnostic; stored-field loan
cases reject already at semantic checking and retain the same verdict through
Core, SSA and LLVM CLI modes.

The five Core loan controls start with valid compiled programs, move an existing
consuming conversion or ownership return into a live loan's scope, require the
specific loan rejection, then restore the original evaluation position and
verify again. They check the Core contract independently of semantic rejection.
Generated IR, binaries and check logs are disposable build output. No historical
baseline compiler, report or receipt is needed.

Additional controls release a different owner while a view remains live, and
release the original owner while an independent text snapshot's view remains
live. Heap-object, buffer and foreign Resource release dumps must retain their
distinct cleanup descriptions without GLib critical diagnostics. Fatal probes
disable core dumps; the driver rejects generated output inside the source tree.

The portable recipe reconfigures an existing build, runs the focused checks,
then optionally builds and runs the relevant established ownership, error,
property, async and finite lazy regressions:

```sh
sh tests/obj-alloc-1/verify.sh regressions
```

The `focused` argument selects just the new checks. The finite registered lazy
regression does not run or reopen the historical strict-set campaign.
The recipe disables ccache and serializes compilation. Historical shared-runner
interruptions remain historical; these commands require no retired control tools.
Compiler options and existing fixture expectations are unchanged.
