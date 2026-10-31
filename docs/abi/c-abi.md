# C ABI capabilities

CABI is Astra's independent foreign physical boundary authority. These profiles
version the supported interop subset, not the platform's C ABI itself.

| Profile | Capabilities |
| --- | --- |
| [scalar-v0](c-scalar-import-v0.md) | Exact signed I32 imports and scalar exports |
| [scalar-ptr-v1](c-pointer-v1.md) | I32 and PTR with accepted foreign ownership contracts |
| [scalar-fp-v2](c-fp-v2.md) | Prior capabilities plus exact binary32 C float and binary64 C double |
| [text-view-v3](c-text-views.md) | Explicit imported borrowed UTF-8 text groups, each PTR plus signed I32 |
| [pod-value-v6](c-value-lp64.md) | Explicit bounded GNU x86-64 SysV LP64 C POD values, INTEGER/SSE channels and MEMORY byval/sret |

Profile selection inspects all foreign declaration/export signatures and C
cleanup contracts. Unused declarations participate. Native signatures and
body-only floating values do not select a foreign profile. Physical plans own
no upstream semantic/IR objects. CABI validates SSA and native export
correspondence before LLVM produces C-convention declarations and wrappers.
NABI remains independent, including native scalar-fp-v3, fp64-v6 and aggregate-v7.

Floating boundaries perform exact representation transport on explicitly
qualified targets. No implicit promotions, typed floating C pointers, C
aggregates, varargs, callbacks or process arguments are implied. See
[C interoperability](../language/c-interop.md) and [ADR 0063](../decisions/0063-c-floating-point.md).

TEXT-1 adds independent [native text-v9](native-text-v9.md). TEXT-IO-1 adds
explicit `text_abi = "utf8-i32"` import metadata and requires `borrowed string`.
Text-bearing C signatures select text-view-v3; text-free signatures retain their
old profiles. There is no implicit char*/void*/aggregate mapping. All foreign
string results and exports still reject. CCode metadata literal rules remain
independent of runtime text.

Surge-5 adds explicit `record_abi="value-lp64"` aggregate parameters/results as
described in [ADR 0116](../decisions/0116-c-by-value-pod-records.md). This foreign
contract remains distinct from native struct value semantics and the earlier
`natural-lp64` borrowed record pointer profile. Qualification is host-specific.
