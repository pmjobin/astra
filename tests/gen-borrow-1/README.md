# Call-scoped Ownable generic borrowing

The user approved `Q11A-RESOURCE-CLASS-BORROW`: one explicit `borrowed T` in a
synchronous nonthrowing top-level native helper and synchronous caller, with copied scalar arguments
and scalar/void result. Exact Resource and Class specializations borrow without
acquiring cleanup. Heap Class borrows retain cleanup in their concrete caller;
heap-consuming generic `owned T` transport remains deferred.

Use the real repository and the reusable external build. The recipe keeps all
generated code, binaries and test evidence outside source, disables ccache and
compiles serially. It uses ordinary Meson commands with an explicit finite test
selection; it runs no retired controller or full registry.

```sh
sh tests/gen-borrow-1/verify.sh focused
sh tests/gen-borrow-1/verify.sh regressions
```

The native driver executes nine readable Astra programs with an independent C
observer of real Resource allocations, nominal cleanup identity and Class
destructor events. Each runs through the ordinary compiler and separately through
LLVM `opt`/`llc` O2. An independently compiled C client calls the generated native
program through an entry bridge; test-only observations at constructor/borrower
entry verify the original nullable pointers and their exact nominal identities.
The bridge changes no production ABI or ownership operation. Neither generic
helper acquires, copies, relocates or destroys its referent. Source field checks
and final destruction independently observe the caller's Class object.

Nine fixtures cover Resource identity/inference, lexical/heap Class reuse,
caller-backed results, null, empty/no-deinit Class, exact derived Class, repeated
branch/loop borrowing, and a completed scalar-producing loan followed by a move
in the next argument, plus bool/integer/f32/f64 copied neighbors/results. Every positive O2 and C-client binary also runs under
unsuppressed Valgrind. An omitted actual specialized release is caught by both
the observer and Valgrind; a duplicate release is caught by the observer before
a second free. The double-free memory-tool path is intentionally not claimed.

The rejection driver checks source diagnostics and absence of executable output
for explicit/inferred calls, shape/capability boundaries, alias/escape/move/copy,
wrong nominal types, unsupported storage and both overlapping consumption orders.
Concrete liveness rejects at the existing CFG authority; symbolic misuse rejects
during generic-definition checking. The nine TAP contract tests independently
mutate Core/CFG/SSA/native input, require the applicable rejection, restore it,
and verify again. A linkage check keeps these contract authorities LLVM-free.

`checks.json`, generated dumps, `abi.json` and `identity.json` under the external
build retain actual commands, exits, traces, memory diagnostics and compiler hash.
No tests require an archived compiler or report. The historical design probes
under `tools/design/gen-borrow-1/` deliberately target the pre-feature base and
are not part of this current qualification.

The finite regression selection covers existing ownership and generic value,
capability, struct, slice/buffer, inference, concrete borrowing, Resource/Class,
Q10B checked records, error, virtual async and lazy contracts. It does not reopen
historical campaigns or qualify CAD, Linux async, GUI/hardware or the full suite.
The existing buffer rejection driver requires fresh output; the recipe gives
each replay its own external directory and preserves earlier evidence.
