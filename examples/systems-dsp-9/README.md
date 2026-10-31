# A65–A72 application witnesses

These are eight distinct Astra programs with deterministic checked behavior.
The [qualification recipe](../../tools/qualification/systems-dsp-9.md) registers
ordinary public compiler builds at O0/O2 and representative O1 (the maintained
recipes currently run all three host optimization levels). Exact commands,
compiler/source/product hashes, exits and output receipts live in the external
build directory under `tests/systems-dsp-9/` and are compacted into the committed
Surge 9 evidence document after the final integration run.

| ID | Source and profile | Checked behavior | Counterpart |
| --- | --- | --- | --- |
| A65 | [CRC](a65-crc.astra), Linux no-libc | CRC-32 of `123456789` is `0xcbf43926`; exit 0, empty stdout; no dynamic interpreter, dependencies or undefined symbols | Wrong checksum exits 65; hosted source/providers rejected in runtime-none |
| A66 | [Double filter](a66-filter.astra), hosted numeric | `f64x2:2048 vectors;8192 exact lanes;NaNs classified` through independent filter/division scalar oracles and typed vector load/store | Invalid dimensions, mixed lane formats and floating saturation rejected |
| A67 | [PCM mixer](a67-mixer.astra), hosted numeric | `saturation:2048 pairs;signed64,unsigned64,PCM16 exact`; both 64-bit lanes and overflow/subtraction endpoints | Wrong signedness rejected; altered/missing saturation rejected by physical proof |
| A68 | [Packet queue](a68-packet-queue.astra), typed arena | `packets:8 closed:8`; two records, zero per-placement heap calls, checked capacity, null admission, expired IDs, LIFO, early return/exception and consumption | Copy/escape/move violations rejected; double drop and bad extents checked; omitted/duplicate cleanup corruption rejected |
| A69 | [Register fixture](a69-registers.astra), mapped host memory | Exit 0; parent hardware-watchpoint witness reports `volatile:9 mapped accesses;exact address,width,value,order` | Invalid width/origin/type/static bounds rejected; dynamic bounds trap; volatile/address/alignment corruption rejected |
| A70 | [Streaming accumulator](a70-stream.astra), hosted integration | Typed packet state plus f64 vector DSP, i64 saturation and volatile status; exact values 42/-10.5; `packets:1 closed:1` | Missing explicit narrowing rejected; resource and memory cleanup checked |
| A71 | [Independent consumer](a71-consumer.astra) and [unit](numeric-unit.astra) | Exit 0; kernel(4) = 20416144; separately compiled O0/O2 cross combinations plus O1, DWARF/GDB identity | Forged target interface rejected and original restored |
| A72 | [Minimal entry](a72-minimal.astra) and [hosted entry](a72-hosted.astra), common [telemetry](telemetry.astra) | Common numeric/volatile result 42; minimal exits 0 without libc; hosted emits `packets:1 closed:1` with explicit resource cleanup | Hosted provider selection rejected under runtime-none; dependency inventories differ as declared |

`linux-start.S` is the identified assembly startup and Linux syscall boundary.
`packet-provider.c` only supplies actual file-descriptor resources; packet
storage/admission/ownership composition is implemented in Astra. The C numeric
oracle is independent test code. The mapped-page allocator and tracing parent
are deliberate host fixtures.

A70 combines four new capabilities. A72 combines runtime selection, short
vectors/saturation and volatile memory, with typed arena cleanup in its hosted
variant. Its minimal variant does not import that hosted resource provider.

The separate [A71 cross export](a71-cross.astra) is additionally emitted for
`aarch64-none-elf` and inspected as **OBJECT_ONLY**. It is extra evidence to
A71's executed host program. Linux no-libc, an AArch64 object and actual no-OS
execution have separate status; no SH-4 or physical-device execution is claimed.
