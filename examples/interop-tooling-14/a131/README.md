# A131 optimized debugger and lifetime application

This native program combines an addressable numeric aggregate, a separately
compiled native module, an owning retained closure, a suspended/resumed virtual
async task and checked exception cleanup. Its independent Clang C provider
checks exact values and three native constructions/destructions on both success
and exception paths. Virtual executor and retained callback providers are linked
explicitly; no GLib/GObject/LLVM/liburing/C++ runtime is linked into the program.

Run `python3 tests/interop-tooling-14/a131-debugger.py ASTRAC EXTERNAL_OUTPUT`.
The 29-command recipe builds public -g O0/O1/O2 products and native interfaces,
verifies actual DWARF, and runs normal/error paths. At O0/O2 it also runs
unsuppressed Valgrind and genuine GDB sessions. Each session stops at an explicit
Source line and independently compiled C functions, inspects real Source caller
frames, reads aggregate category/count/total, capture gain/call count, resumed
seed 11, checked boolean parameter and the module's addressable corrected value
42, then requires a real zero process exit and exact cleanup.

The closure's optimized input may be unavailable; only its backed capture is
required readable there. Async metadata names an actual Source parameter and
reads its persistent frame field with a bounded DWARF value expression. No
fictional temporary, complete expression evaluator or universal optimized
variable recovery is promised. Backtraces can retain internal `astra.fn.N`
linkage names alongside actual Source coordinates. The matching mutation proof
checks Class/frame geometry, restoration and released upstream graphs.
