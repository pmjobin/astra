# Selected Windows COM exports

The first `[COMExport]` profile targets the Windows x64 ABI with SDK `IUnknown`,
two explicit application IIDs and registration-free in-process construction.
It composes with the [opaque C Class bridge](c-class-exports.md) on one plain
intrusive `[Shared]` root. It does not add a second object reference count.

```astra
[COMExport(value_iid="849ad154-8d1e-4c63-9ea2-14329b022001",
	scale_iid="849ad154-8d1e-4c63-9ea2-14329b022002", threading="constructing")]
[CExport(name="counter", property="value")]
[Shared]
class Counter {
	private int data;
	init(int value) { this.data = value; }
	property int value {
		get { return this.data; }
		set(int value) { this.data = value; }
	}
}
```

IIDs must be distinct canonical GUIDs identifying application interfaces;
IUnknown and the zero GUID are refused. Spelling case is normalized. The Value
interface has IUnknown slots 0–2 followed by `HRESULT Get(LONG *)` and
`HRESULT Set(LONG)`. Scale has IUnknown slots 0–2 followed by
`HRESULT Scale(LONG, LONG *)`. Their pointers differ; every successful query for
IUnknown returns the same canonical Value view. QueryInterface acquires exactly
one native strong reference. Failed queries clear out and acquire nothing.

Compile with `--target=x86_64-w64-windows-gnu -c`. The compiler checks the closed
Windows source domain and refuses unsupported transports and host services.
`--emit-com-header` emits checked SDK declarations. `--emit-com-source` emits a
C++17 adapter using those exact declarations and the opaque C bridge. Both write
only stdout after the native/C ABI/LLVM verifiers succeed. Compile the adapter
with an explicit Windows x64 SDK toolchain, compile `foreign-14.c` as C11 and
link both with the Astra object and the SDK COM/UUID providers. The compiler
does not download tools, register a class, or infer Windows libraries.
The portable end-to-end recipe is `tests/interop-tooling-14/com-export/build.py`.

`counter_com_create(int32_t, IUnknown **)` creates a native root and returns one
COM owner. `counter_as_com(counter_handle *, IUnknown **)` acquires a COM owner
over a backed C owner. Adaptation caches a stable COM personality while any
native/C/COM owner exists. All AddRef/Release operations use the native strong
counter. Last strong release destroys the native payload once, then deletes the
COM personality and C wrapper. Native weak owners preserve only the allocation
metadata; after expiry, upgrade returns null without reading retired wrappers.
Every client and weak owner must retire before unloading its provider DLL.

Data, QI and adaptation require the constructing thread and its original COM
apartment type/qualifier. The factory requires actual COM initialization. Missing
initialization returns `CO_E_NOTINITIALIZED`; a foreign thread or changed
apartment is refused with `RPC_E_WRONG_THREAD`. AddRef/Release remain atomic
lifetime operations with backed owners. Monitor composition, agility,
marshaling, aggregation, CLSID registration, cross-process activation and WinRT
are outside this selected profile. A monitor cannot establish COM agility.

Get and Scale clear valid out slots before failure and return `E_POINTER` for a
null out slot. Scale accepts value and factor in 0–100, preventing overflow;
factor zero succeeds with `S_FALSE`, other valid factors with `S_OK`, and invalid
inputs with `E_INVALIDARG`. The adapter contains no foreign exception unwind.
Allocation failure maps to `E_OUTOFMEMORY` and the factory releases partial
native ownership. Assignments of native shared owners still move and `clone()`
retains explicitly.

The checked immutable COM contract carries IID, vtable slots, QI ownership,
platform convention and required context checks through Core/CFG/SSA/Native/C
ABI identities. Mutation proofs reject substituted IIDs, wrong vtable slots,
missing QI acquisition, missing context checks and changed platform convention,
then restore healthy lowering. The existing physical bridge proof also rejects
changed native calls, thread guards and last-root retirement operations.

Native Windows 11 execution of independently compiled clients has passed against
real Astra O0/O1/O2 DLLs. The client declares SDK interfaces and IID literals
without generated headers and tests canonical identity, distinct C/COM/native
addresses, counts, HRESULT/out, C/COM data coherence, actual STA/MTA, thread and
apartment refusals, restored calls, cached identity, weak expiry and 131 exact
payload destructions per run. Executable/DLL hashes are captured in the guest
alongside every exit code. The read-only CD is ejected after execution and
persistent VM XML remains byte-identical. No registry or package changes occur.
[COM import](com-imports.md) now has separate native Windows execution evidence.
Full Surge 14 acceptance still requires the remaining campaign gates.
