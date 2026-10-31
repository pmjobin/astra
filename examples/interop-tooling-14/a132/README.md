# A132 installed PCM exchange service

This distinct application accepts eight little-endian signed PCM samples over
TCP and eight over UDP, mixes them with native eight-lane saturating arithmetic,
and sends the exact result through both transports. The independent Python
clients supply real runtime data, fragment the TCP request, verify every output
byte and sender endpoint, and exercise truncated TCP plus short/oversized UDP.

The source explicitly selects `ThreadedExecutor` with three workers. PCM record
construction runs off the main thread. An owning generic `Bag<Reading>` stores
eight records in a 64-aligned bounded region; all those owners retire within one
synchronous call on one worker before the next suspension. Ordinary heap buffers
and an explicitly cloned native `[Shared,Monitor]` ledger remain in the async
frame. Instrumented provider objects verify same-worker region allocation/
retirement, exact region high-water/live counts, eight exact record destructions,
one native ledger destruction and three descriptor closes. The counters use C
atomics; they do not replace native ownership or monitor synchronization.

Run `python3 tests/interop-tooling-14/a132-installed-system.py ASTRAC EXTERNAL_OUTPUT`.
For the required installed release profile, add `--prefix INSTALLED_PREFIX`.
That mode requires the compiler, library/provider sources and sample sources
from the independent installation, copies the consumer outside the checkout,
and uses the normal public CLI with explicit object/library inputs. The recipe
labels an in-development compiler run separately from installed qualification.
An omitted threaded provider must fail linking; no fallback or hidden runtime
link is selected. The executable has no GLib/GObject/LLVM/liburing/C++ dependency.

Public O0/O1/O2 execute boundary and deterministic random data, malformed-wire
and cleanup paths. O0/O2 successful and failing runs additionally pass
unsuppressed Valgrind with every leak kind an error. The selected application
profile is hosted GNU Linux loopback TCP/UDP with an explicit POSIX threaded
provider; Linux io_uring and bare-metal qualification remain separate campaign
checks. This is not a universal networking or allocator-thread-safety claim.
