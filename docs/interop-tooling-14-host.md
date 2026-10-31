# Native Windows COM host qualification

The existing `win11` libvirt session VM executed an independently compiled C++
provider DLL and C++ client on Windows build **10.0.26100.8894, AMD64**. The
qualified host probe uses registration-free `LoadLibrary` plus an explicit
factory; it never registers a COM class or invokes a registry class factory.
This establishes a usable native execution host. **It does not implement or
qualify Astra `[COMImport]` or `[COMExport]`.**

The selected ABI is Windows x86-64: 64-bit pointers, 16-byte GUID, 32-bit HRESULT
and LONG, ordinary Windows C factory calls and SDK `STDMETHODCALLTYPE` virtual
interface methods. Provider and consumer compile separately using Fedora MinGW
GCC 16.2.1. Their MinGW support libraries link statically; inspected PE imports
require only existing Windows KERNEL32/msvcrt and, for the client, ole32.
Nothing was installed in Windows.

Executed checks:

- Two distinct application IIDs produce different interface pointers; successful
  QueryInterface retains. IUnknown queried through either view equals the
  original canonical root. Unknown IID returns E_NOINTERFACE and clears output.
- Calls return exact integer data, S_OK, nonfailing S_FALSE, E_POINTER and
  E_INVALIDARG, with checked null/out behavior.
- Main-thread STA and worker-thread MTA initialization both execute real
  CoInitializeEx. A borrowed interface remains backed by main-thread strong
  references until the worker joins. A wrong-thread data call returns
  RPC_E_WRONG_THREAD and clears its output before accessing payload state.
- Independently observed Release counts descend 4, 3, 2, 1, 0. Provider payload
  destruction remains zero before final Release and becomes exactly one after.
  The client unloads its DLL and uninitializes COM.

The probe does not establish cross-apartment marshaling, agility, activation,
aggregation, weak-reference support, callback shutdown, general cross-thread
lifetime calls, or Astra native/foreign lifetime translation. Those remain
separate compiler and runtime obligations in the active campaign.

## Reproducible source and receipts

Sources are in `tests/interop-tooling-14/com-host`. Build with a supported MinGW
C++ toolchain and explicit external output directory:

```sh
python3 tests/interop-tooling-14/com-host/build.py \
	--cxx /opt/mingw/usr/bin/x86_64-w64-mingw32-g++ \
	--sysroot /opt/mingw/usr/x86_64-w64-mingw32/sys-root \
	--output /tmp/astra-com-host --iso
```

The illustrative `/opt/mingw` must identify an actual installed/extracted
toolchain; it is not an implicit build prerequisite or environment override.
`build.json` records commands, exact source/product hashes, toolchain and PE DLL
dependencies. `--iso` uses genisoimage to create optional read-only test media.
Run `run.cmd` on the approved Windows host, or run `host-client.exe
ABSOLUTE_PROVIDER_DLL` directly from an isolated test directory. The batch recipe
also returns inventory/stdout/exit markers over an already configured COM1;
it does not install or configure serial devices.

The accepted host receipt is external:
`runtime/native-current/windows-host-probe-3/result.json`, with raw serial output
and the exact build receipt for `build/interop-tooling-14/com-host/host-wudh1qs_`.
Earlier attempts are retained: missing bridge, denied PowerShell launch,
unavailable VM HTTP transfer, foreground-window input and a corrected batch
redirection that initially omitted the numeric exit marker. Incomplete receipts
failed validation; they were not counted as successful runs.

The native probe completed with `ASTRA14_HOST_EXIT=0` and all required markers.
The temporary test CD was ejected. Persistent VM XML before and after was
byte-identical, SHA-256
`658b372e1d9571e2dbb000d8cd92cc91c48626b9deb3aafc34ab70a9592d51e1`.
No snapshot operation, registry editing, account/security configuration, Windows
package installation or COM registration was performed. A task-only HTTP transfer
endpoint was stopped.
The VM remains running for the subsequent compiler-generated adapter campaign.
