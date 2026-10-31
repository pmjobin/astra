# Selected Windows COM imports

`[COMImport]` introduces a nominal owning interface carrier over the selected
Windows x64 COM ABI. The foreign producer supplies the actual object and
IUnknown implementation. The compiler-generated SDK adapter contains no native
Astra Class layout and adds no intrusive native reference count to that object.

```astra
[COMImport(name="remote", iid="849ad154-8d1e-4c63-9ea2-14329b022001",
	view="value", threading="constructing")]
interface RemoteValue;

int use(void* backed_unknown) {
	int status = 0;
	owned RemoteValue value = remote_acquire(backed_unknown, &status);
	if (value == null) { return status; }
	int result = 0;
	return remote_get(value, &result);
}
```

The first profile requires a global interface declaration, unique explicit
symbol prefix, application IID, `view="value"` or `view="scale"`, and
`threading="constructing"`. Value has SDK IUnknown slots followed by
`HRESULT Get(LONG *)` and `HRESULT Set(LONG)`. Scale has IUnknown followed by
`HRESULT Scale(LONG, LONG *)`. Arbitrary members, inheritance, agility and
native-module serialization are refused. Multiple source files can share the
same checked compilation. Windows has 64-bit pointers and 32-bit HRESULT/LONG;
SDK adapter compilation asserts these widths.

For prefix `remote`, the compiler supplies typed source callables:

| Callable | Ownership and result |
| --- | --- |
| `remote_acquire(borrowed void*, borrowed int*)` | Query the explicit IID; return one owned nominal wrapper and write HRESULT |
| `remote_clone(borrowed RemoteValue, borrowed int*)` | Allocate one new wrapper and AddRef once; write HRESULT |
| `remote_get(borrowed RemoteValue, borrowed int*)` | Value only; return HRESULT and write copied integer |
| `remote_set(borrowed RemoteValue, int)` | Value only; return HRESULT |
| `remote_scale(borrowed RemoteScale, int, borrowed int*)` | Scale only; return HRESULT and write copied integer |

The factory input must be an actual backed IUnknown pointer from the selected
external producer. The caller retains its owner and loaded DLL while acquisition
runs. No source raw cast substitutes for QI. Each acquired or cloned wrapper owns
one foreign interface reference. Assignment moves with `move`; an explicit
clone call retains. Normal scope exit, early return and explicit `release`
retire one foreign reference and the separate wrapper exactly once. A nominal
Value carrier cannot be substituted for a Scale carrier or erased through an
unrelated C import.

Acquisition clears its status slot before failure, preserves positive HRESULTs,
releases an acquired stray interface returned alongside failed QI, and refuses
success with a null interface as `E_UNEXPECTED`. Wrapper allocation failure
releases partial QI ownership and reports `E_OUTOFMEMORY`. Clone allocates before
AddRef, so its allocation failure acquires no reference. Get/Scale clear valid
out slots before failure and copy an external out value only on HRESULT success.
An external failure that writes a dirty out slot cannot leak that value to Astra.

Data and clone require the constructing thread and original COM apartment.
Missing initialization yields `CO_E_NOTINITIALIZED`; a changed apartment or
foreign thread yields `RPC_E_WRONG_THREAD`. Imported owners must also retire in
their constructing context: a cleanup in a wrong context traps before invoking
the foreign producer. The selected Windows source profile excludes thread/actor
transfer and asynchronous ownership. No foreign unwind is introduced.

Use the same `--target=x86_64-w64-windows-gnu`, `--emit-com-header` and
`--emit-com-source` workflow as [COM export](com-exports.md). Explicit SDK
toolchain/link inputs build the generated C++17 adapter and `foreign-14.c`.
The complete recipe is `tests/interop-tooling-14/com-import/build.py`. The
compiler does not install tools, register COM classes or choose a foreign DLL.

Frozen nominal IID/cleanup identities are checked in semantics, Core, CFG, SSA
and a native ABI import inventory. The C ABI sidecar checks exact acquisition,
clone, method, result, ownership and integer out roles. Physical LLVM call
bindings retain exact arguments and the selected Windows target. The generated
SDK source is emitted only after the native/C/LLVM verifiers succeed. Mutation
proofs cover lost contracts, changed IIDs/vtable slots/context, lost native
inventory and host-target relabeling, with restoration and upstream graph release.

Real Windows 11 O0/O1/O2 consumers passed against an independently compiled C++
producer. Receipts include guest file hashes and process exits, two IIDs and
actual vtable/data calls, explicit clone/move and early cleanup, failed and
positive HRESULTs, partial QI out cleanup, null-success refusal, wrapper and
clone allocation failure, actual STA/MTA and wrong-context refusal, restored
calls, 128 repeated source executions, exact provider teardown and retirement of
every tracked import wrapper before DLL unload. These are native Windows
execution results, not Wine compatibility results. Full Surge 14 acceptance
still requires the remaining campaign gates and final frozen-source replay.
