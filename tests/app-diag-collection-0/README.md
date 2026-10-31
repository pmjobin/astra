# Diagnostic collection application checkpoint

`sh tests/app-diag-collection-0/verify.sh focused` builds/selects the verified
external compiler and existing hosted-entry LLVM emitter, then runs one Meson
registration. `regressions` also runs nine existing owner/generic/buffer/object/
text/error registrations. The shared build defaults to
`~/Workspace/codex/work/astra/build`; routing and debug, werror=true, b_pch=false,
linux_async=false options are checked before reuse. Compilation is serial with
ccache disabled. Each application test run preserves previous receipts in a new
`build/tests/app-diag-collection-0/execution/run-*` directory; `current.json`
points to the latest. Missing tools fail explicitly.

[current.astra](current.astra) is the current-language application: concrete
diagnostic objects own immutable readonly string snapshots, and a monomorphic
bag owns two named nullable child slots. Its `append_or_drop` consumes even on
false. The successful witness checks room and appends only two entries; reporting
full capacity neither allocates a third slot nor promises failed-insertion
rollback. Short borrowed helper calls inspect child fields. A `while` traversal
renders immutable receiver-bounded message views. No new C application helper,
raw pointer registry, generic class or resizing implementation is used.

Existing hosted providers validate/snapshot argv and write UTF-8 output. Runtime
argument text is copied into the first message snapshot, then independently
copied into the second. Astra checks different Class identities, metadata and
equal content. Empty, precomposed `café`, combining `cafe\u0301`, four-byte `🖤`,
empty-text and early-exit scenarios are checked for exact output/exit under
native and independent opt/llc O2 execution. Standard-allocator unsuppressed
Valgrind runs require zero errors, suppressed errors and live blocks. The
unchanged ERROR-1 snapshot fixture additionally checks that a copy survives its
source owner. These are runtime-provided snapshots, not an Astra text builder.

[storage.astra](storage.astra) checks a copied generic record member, a scoped
fixed-array slice and temporary numeric-buffer borrowing followed by replacement.
Replacement discards old storage and produces zeros; it is not capacity growth.
The seven [probes](probes) distinguish deliberate declaration-grammar exclusions
from semantic element/copy/lifetime/type rejections. The driver checks parse
classification, exact diagnostic text, exit 1, empty stdout and no executable
through check/native routes. Existing expectations and compiler sources are
untouched. Initial reductions exposed the child-field helper and fixed-array-only
`slice(...)` restrictions; the final legal sources use their established forms.

[desired.spec.txt](desired.spec.txt) is a 30-line **NONCOMPILING SPEC** and is never
passed to the compiler or a positive registry. It combines proposed APIs and
iteration/ownership syntax to express intent; no part of that spelling is
approved by these tests. Byte validation/ownership, owning indexed storage and
generic member abstractions remain separate proposed deliveries.

See requirements and next-milestone recommendation
for measured results, source authorities, D01–D08, costs and unresolved choices.
PASS here is for this contract/witness only; Q11/Q19/Q20 and the three campaigns
are not complete. No full suite, LAZY Q4, CAD, real liburing, GUI or target gate is
run by this recipe.
