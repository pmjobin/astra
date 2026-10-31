# M16 declarations-v1 Windows C object profile

The explicit declarations-v1 C Class profile extends the Windows x64 object
backend to ordinary unique/shared roots, copied wide integers and floating values,
closed scalar PODs, bounded buffers/text, checked exceptions, owner transfer and
call-only typed callbacks. Checked admission and the detached SSA backend each
validate the target domain. An artifact retains its exact Windows target and
profile admission; it cannot be relabeled from or to a host artifact.

This opt-in is separate from the historical Windows profile. A source without a
new C declaration keeps its previous bounded admission. Monitor/Actor/async
runtime services, custom allocation policies, vectors, enum storage and native
module linking are not admitted by this intermediate Windows extension. The
foreign-metadata native-unit extension and target personality selection remain
pending M16 work. This profile does not qualify declaration-driven COM or GObject.

Native layouts and natural foreign POD layouts use the selected target machine.
The Windows declaration profile checks 64-bit pointers and the actual field
size/alignment/offset witnesses. C scalar declarations use explicit stdint widths,
C99 bool, binary32 and binary64; they do not reinterpret Windows long as a 64-bit
C integer. Text descriptor offsets and record collection storage retain their
independent complete layout checks. The old profile's float/wide refusals remain
covered by unchanged tests.

`windows-c-matrix.py` consumes actual successful hosted registry receipts from the
repository's authored M16 C recipes. It revalidates fixture hashes and independent
native assertions, mirrors generated case sources, reruns the compiler for the
Windows target, checks that generated headers/forwarders match their independently
used declarations, and cross-compiles the same C clients/providers. Every executable
imports only system kernel32/msvcrt DLLs. Cross-build success is explicitly separate
from native Windows execution.

`windows-c-media.py` packages at most 48 cases per read-only medium. Its batch file
copies and runs only task executables in a new `%TEMP%\Astra16-C-*` directory.
`windows-c-capture.py` reads the existing authorized serial console for at most
120 seconds, restores terminal state, and checks each filename/hash/exit association
and exact expected assertion markers. Failed or incomplete attempts remain evidence.
Each batch restores temporary live media; the user's session stays running and
persistent VM configuration is compared with its initial XML.

`windows-machine.py` separately builds independent and generated-header consumers
that check LLP64 widths, bool, scalar argument/result behavior, positive/negative
binary32/binary64 gradual underflow, the incoming SSE environment and Windows
process heap integrity. Heap integrity is not a leak measurement. Native execution
receipts and the intermediate slice ledger identify the exact observed scope.

The first complete native Windows run passed 266 of 278 C cases. All twelve
scalar clients failed under the global calloc failure hook: a traced cold run
showed a denied 32-byte MinGW emulated-TLS bootstrap allocation; a warm run of the
same client passed every original assertion. The Windows-only scalar test setup
now initializes runtime thread identity before injecting failures into native
root/wrapper allocation. The original OOM, retirement, thread and ownership
assertions remain intact. All twelve variants then passed on native Windows.
The failed receipts and traced cold/warm control are retained. The batch helper
also now treats negative process exits as failures; the serial verifier already
rejected those exits even when the old batch aggregate marker was zero.

The combined observed set is 278 C interoperability cases and six independent
machine probes at the same compiler identity, with exact per-file hashes and
assertion markers. The latter observed MXCSR 0x1f80, exact gradual-underflow bit
patterns, Windows LLP64/C99 bool widths and successful process-heap validation.
The slice also records 48 hosted registrations, the refreshed scalar registration,
20 foreign contract suites and two Windows contract suites under Valgrind. These
are intermediate qualifications, not the required final strict full registry.
