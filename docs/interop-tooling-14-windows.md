# Selected native Windows object qualification

`--target=x86_64-w64-windows-gnu -c` selects the initial
`windows-interop-object-v1` profile. It emits a Windows COFF object through the
normal checked/Core/CFG/SSA/native ABI/C ABI/LLVM pipeline. Link the object with
an explicit Windows C toolchain. The Linux compiler does not invoke its Linux
linker on that object or produce a Windows process-entry wrapper.

The initial domain is copied words of at most 32 bits, booleans internally,
opaque `void*` C channels, plain native intrusive `[Shared]` Classes and their
intrinsic Weak handles. Native assignment transfers; `clone()` retains explicitly.
Its selected calloc/free ABI has 64-bit pointers and size_t, natural object
alignment and 64-bit internal atomic strong/weak counters. Source-wide integers,
floating values, records, boxed sharing, owning fields, custom allocators,
inheritance, Monitor/Actor/ThreadBound/Singleton, closures, native modules,
async/throws and alternate C transport profiles are excluded. The existing
Linux and no-OS profiles retain their separate domains.

Checked source and SSA both enforce the domain. The physical target requires
recorded Windows source admission and refuses a host artifact relabeled as
Windows or the reverse. All ordinary ABI, class, exact allocation and Shared
atomic/order/retirement proofs still apply. `--target-info` reports the domain;
`--dump-llvm` configures the selected Windows target before printing its IR.
This is a target/lifetime foundation for the approved foreign adapters.
**It does not implement `[COMImport]` or `[COMExport]`.**

## Executed native evidence

The existing Windows 11 VM (10.0.26100.8894, AMD64) executed independently
compiled MinGW C clients linked with actual Astra objects at O0/O1/O2. Each
executable passed word/pointer calls in both directions, nonnull/null pointer
identity, assignment transfer, explicit clone, weak upgrade while live and after
expiry, and exactly 128 observed native payload destructions with the expected
final value. The three process exits and the batch exit were zero. Each copied
guest executable's certutil SHA-256 matched its build receipt.

The first complete receipt is
`runtime/native-current/windows-native-execution-1/result.json`, paired with
`build/interop-tooling-14/windows-native/windows-native-4nrevaeo/build.json`.
After physical target-admission guards, the same component passed again in
`runtime/native-current/windows-native-execution-2/result.json`, paired with
`build/interop-tooling-14/windows-native/windows-native-xa6ck9sv/build.json`.
Source-refusal and link-dependency checks precede execution; successful
cross-compilation alone is not counted as native acceptance. Earlier rejected
profile attempts remain recorded, including initially excluding the intrinsic
Weak handle inventory and confusing internal Shared i64 counts with public
wide C ABI channels. No unsupported source-wide ABI was enabled to pass them.

Build and run using actual installed/extracted toolchain paths:

```sh
python3 tests/interop-tooling-14/windows-native/build.py \
	--compiler /absolute/astrac \
	--cc /absolute/mingw/usr/bin/x86_64-w64-mingw32-gcc \
	--sysroot /absolute/mingw/usr/x86_64-w64-mingw32/sys-root \
	--output /absolute/external/windows-native --iso
```

On the approved Windows host run the media's `run.cmd`. It copies executables
into a new `%TEMP%\Astra14Object-*` directory and uses an existing COM1 serial
device for evidence; it never configures that device. The shared serial capture
recipe uses `--profile native` and the exact build receipt, and restores the
host terminal settings afterward. No Windows package, account, registry, COM
registration, security setting or snapshot was modified. The temporary CD was
ejected and persistent VM XML remained byte-identical, SHA-256
`658b372e1d9571e2dbb000d8cd92cc91c48626b9deb3aafc34ab70a9592d51e1`.

The registered Windows profile proof passed two subtests covering target admission and
ordinary-LLVM-valid mutations of atomic ordering, exact root retirement and
native call convention, with healthy restoration and upstream graph release.
It rejected and restored 55 atomic-order, 10 live-root retirement and 17
native call-convention mutations, plus three target-admission controls.
Those mutations complement actual execution; they do not qualify COM layout,
IID, HRESULT, interface ownership or wrong-thread adapter behavior.
