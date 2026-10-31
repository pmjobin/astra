# Surge 14 C union and boolean profile decision

Status: explicitly approved by the user in the Surge 14 native interaction.
This approves both bounded contracts; implementation/execution qualification
remains a separate gate.

The [union prototype](../language/c-unions.md) uses explicit Source record
projections. `Repr(layout="C-union",members="integer:i64,bits:u64",active="integer")`
exposes only the selected member of an 8-byte, 8-aligned INTEGER-class union.
There may be 2–8 uniquely named `i64`/`u64` members. A distinct nominal projection
selects another member; no type punning or borrowed mutable alias is admitted.
The tagged form additionally exposes leading `i64 tag`, requires an explicit
case 0–2147483647, and has extent 16/alignment 8. Every C import/export argument
and result checks its tag; a mismatch traps before forwarding or typed exposure.
An untagged provider remains responsible for the declared active member.

The proposed boolean extension requires `bool_abi="c99"` on typed `CImport` or
`CExport` functions. It admits copied Source `bool` as C99 `_Bool` only on the
selected GNU x86-64 Linux SysV ABI, with LLVM i1 channels and required zero-extension
attributes at declarations, wrappers and calls. It excludes pointer/record bool
storage and implicit integer conversion. Existing unannotated/legacy bool
refusals remain. Both source and physical verifiers must retain the profile and
reject missing or altered attributes. Independent strict C11 producers/clients
must execute both directions at O0/O1/O2 before acceptance.

These profiles alter explicit C boundaries; they add no metadata, foreign
runtime, allocation, reference counting or linking to programs that do not use
them. They do not extend the approved Windows COM or Linux GObject object ABI.
