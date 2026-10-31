# Transitively owned child objects

Run from the real repository root with one external build. Use standard
interactive Codex and direct Meson/Python commands, respecting the active task's
scope and coordinating reuse with linked worktrees.

```sh
export PM_CODEX_BUILD_DIR="$HOME/Workspace/codex/work/astra/build"
export PM_CODEX_RUNTIME_DIR="$HOME/Workspace/codex/work/astra/runtime"
mkdir -p "$PM_CODEX_RUNTIME_DIR"
sh tests/obj-field-2/verify.sh focused
# The finite existing ownership/error/property/lazy/virtual-async fence:
sh tests/obj-field-2/verify.sh regressions
```

The recipe disables ccache, uses strict `werror=true`, serial compilation and
at most two concurrent regression registrations. All generated outputs use the
external build; task-only audit notes use runtime. The driver rejects outputs
inside the source tree and disables core dumps. GNU `realpath`, Meson/Ninja,
Vala/GLib, LLVM 22 (`opt`, `llc`) and the existing Linux/glibc C toolchain are
required. Installed Valgrind runs unsuppressed; absence is explicitly untested.

Optional Linux support stays `linux_async=false`. This recipe has no full-suite
mode and performs no liburing probe or kernel qualification. The preserved
`liburing-probe.c` and historical validation record are independent evidence;
current scope and fresh results are in
the native milestone validation.

`children` proves equal-valued distinct objects, retained child identity and lazy
cache through parent moves/forwarding, independent parents, a grandparent chain,
and coexistence with lexical/caller-managed parents. `replacement` checks direct,
method, nullable and deinit replacement, inherited parent fields and synthesized
destruction. `checked` executes acquisition failure after committing a field,
failed and successful replacement factories, and a later-argument abort that
retains both named incoming authority and the old field.
`lifecycle` checks derived owned children before base teardown and coexistence
with an inherited readonly text snapshot. `async-replacement` moves a local
child into a live field before cancellation, proving the moved local no longer
has frame cleanup responsibility.

`declarations` checks heap-domain constraints through uncalled constructors,
forwarding and base initialization, and a valid null-only factory. The
`async-boundary` witness uses the existing GNU LP64 x86-64 Linux virtual support
object to complete one child-owning parent and cancel another after moving its
owner across suspension. Frame retirement uses the same exact plain-class
destructor plan as ordinary cleanup, without reading a polymorphic header from
plain storage. This adds no Class task result or captured Class parameter.

Each witness executes through the public compiler and independently through LLVM
O2 verification, object emission and C linkage. Three test-only IR bridges observe
actual child constructor/probe/destructor receivers before optimization, without
changing allocation, field or owner operations. The C observer checks identity,
exact death order and exactly-once destruction. Installed Valgrind uses no default
or custom suppressions and must report zero errors and zero live bytes/blocks.
Negative source forms assert precise diagnostics at semantic/Core/CFG/SSA/LLVM
CLI boundaries. The separate TAP contract test mutates otherwise valid Core, CFG
and SSA to reject wrong cleanup authority, omitted retirement and borrowed-field
ownership, then restores and revalidates each program.
Transfer of a child with a surviving stored readonly-text loan is rejected
independently in Core, CFG and SSA. Incoming factories cannot receive a possibly
aliasing containing owner while its field destination is pending.

Constructors cannot declare escaping throws. Recoverable heap OOM, trap unwinding,
retained child borrows, field extraction, polymorphic child slots, owning struct
fields and general Q08 links are not qualified here.
