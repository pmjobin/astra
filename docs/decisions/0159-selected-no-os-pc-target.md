# ADR 0159: Selected no-OS x86-64 PC

The user approved the probed x86-64 PC target in the Surge 12 interactive
session. This selects an emulated profile, with no physical hardware claim.
Exact tool/firmware hashes and complete discovery outputs are retained in
external `runtime/native-current/target-probe.json`.

The installed executable is QEMU 10.2.2 (Fedora package
`qemu-10.2.2-1.fc44`), machine `pc-i440fx-10.2`, CPU `qemu64`, TCG,
one processor and 64 MiB RAM. Firmware is the installed read-only
`/usr/share/seabios/bios-256k.bin`. LLVM, Clang and LLD are 22.1.8.
No guest operating system, host networking, physical device, package install
or firmware download is selected.

The public compiler selects `--target=x86_64-none-elf --runtime=none -c`.
Every generated function disables the SysV red zone. Startup establishes
64-bit mode, an aligned 64 KiB stack, identity mappings for the first four GiB,
x87 initialization and MXCSR `0x1f80` before calling Astra's C export. The
initial source subset remains closed numeric/control/fixed storage; adding
owners, device operations and checked policies requires separate compiler
proofs and executions within this campaign.

The explicit [startup](../../examples/freestanding-allocation-12/pc-start.S)
and [linker script](../../examples/freestanding-allocation-12/pc.ld) produce
an ELF64 for audit and a raw Multiboot-1 address-header image for QEMU's loader.
Multiboot entry is 32-bit protected mode with the required EAX magic; startup
owns the transition to long mode. ROM load begins at `0x100000`; DATA runtime
storage begins at `0x200000`; BSS, page tables and stack follow, below `0x300000`.
The linker asserts both budgets and the exact boot header. Startup explicitly
copies DATA and clears BSS after poisoning both, allowing an independent
omitted-initialization control. The serial primitive only serializes bytes
returned by Astra application code. The 16550A uses port `0x3f8`, 115200/8N1;
this is port I/O, and does not qualify typed MMIO by itself.

The [guest recipe](../../tests/freestanding-allocation-12/guest.py) records
actual commands, UART bytes, exit, source/product hashes, ELF inventory, map
and disassembly. Each guest has a 15-second host watchdog and no automatic
reboot. The explicitly modeled `isa-debug-exit` device at port `0x501` turns
guest value 16 into emulator exit 33; this is an emulator test dependency.
Exit alone is insufficient: the independently expected serial bytes must match.
The source mutation changes the arithmetic and therefore the observed bytes.

Core startup now installs fatal exception gates for #UD, #GP and #PF. They
serialize a hexadecimal exception number and terminate through the explicit
failure channel. No unwinding or resumption after a fatal source check is
claimed. A separately selected vector-3 gate preserves general and x87/SSE
state, calls the checked source `int astra_trap_handler(int,int)` export, and
returns with `iretq`. The handler cannot call or acquire external effects;
hardware IRQs remain masked and no `[Interrupt]` support is claimed.

Boot-format references are the [Multiboot specification](https://www.gnu.org/software/grub/manual/multiboot/multiboot.html)
and QEMU's [documented `-kernel` Multiboot route](https://www.qemu.org/docs/master/system/qemu-manpage.html).
These describe the route; installed-product execution is the qualification.

Stop conditions remain wrong boot/layout/target identity, unproved memory
effects or ownership, an unavailable required device, a dependency/approval
blocker, or failed guest/runtime evidence. Linux no-libc and historical
AArch64 OBJECT_ONLY results remain separate. F1–F9 acceptance is pending.
