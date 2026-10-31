# TEXT-OWN-1A focused qualification

Run the external-build recipe from the repository root:

```sh
tests/text-own-1a/verify.sh focused
tests/text-own-1a/verify.sh regressions
```

`PM_CODEX_BUILD_DIR` selects the reusable external build. `PM_CODEX_RUNTIME_DIR`
must also name an external task area; capture task logs there. The recipe
verifies both paths, source routing and the qualified Meson options before
reuse. Compilation is serial with ccache disabled; generated source,
objects, LLVM, binaries and JSON evidence stay outside the checkout.

The eight contract subtests independently mutate and restore Checked,
Core, CFG, SSA, native and actual LLVM contracts. They cover forged byte origins
and signed counts, validation identity, canonical copy acquisition, cleanup
responsibility, receiver association and physical byte-count/read/guard order.
Each expects a typed verifier rejection, then re-verifies restored valid input.
The huge-count control forges IR over a one-byte array; it does not allocate or
claim a public two-gigabyte runtime input. A separate physical mutation replaces
the actual validator call count with negative I32 and requires rejection.

`positive.astra` is an independent readable Astra application: empty and equal
distinct owners; runtime-written ASCII, precomposed/decomposed text, four-byte
scalars and embedded NUL; input mutation and retirement; an owned factory result
whose input dies before return; concrete child storage; a completed receiver loan;
normal, early and later checked exits. `malformed.astra` handles public checked
errors, retaining an unrelated owner and unchanged byte input. The Python recipe
generates a separate source program for each malformed encoding branch and
tests eight scalar boundaries, including U+10FFFF and a noncharacter. The small
smoke and documentation example are separate compiled programs.

Every source program has actual compiler-native and independently emitted,
verified, opt-O2/llc-O2 versions. Both use the real standard allocator under
unsuppressed Valgrind, requiring zero errors and zero live blocks. New lifetime
source negatives must parse and fail semantically/native with no executable.
Owner replacement remains unsupported at the existing Class-binding rebind gate;
its rejection is not claimed as a separate receiver-loan analysis proof.
The predecessor's implicit-conversion negative remains unchanged and rejecting.
Copies of the new library are independently corrupted to test nomination,
constructor, getter and diagnostic policy; the canonical library hash is
checked after each case. No historical fixture/expectation is edited.

The separate private observer instruments the **actual factory's** input and
successful owner publication and its ordinary destructor, then links the same
Astra program. It checks the qualified `{PTR,I32}` snapshot layout against
real calloc extents, exact copied bytes/count, input/payload independence, distinct
live owner and payload addresses, exact destructor order and one payload/object
free. It is test instrumentation, not the source factory implementation or a
public C adapter. Unmodified standard-allocator Valgrind runs are separate.
Five isolated allocation faults check input, message, payload, error-object and
diagnostic fatal sites, in both observed native and O2 programs. No unwind or
catchability claim is made for those signal-terminated runs. An unused-feature
control selects no message library and gains no validator or allocator symbols.

No full registry, GUI/hardware, CAD, liburing, LAZY or generic-container
qualification is implied. Q19A's finite byte ingress is separate from the open
Q19/Q20/Q21 and broader Q11 work.
