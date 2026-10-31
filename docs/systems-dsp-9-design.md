# Systems and DSP scope

The implementation extends the existing typed vector and explicit saturation
operations with `f64<2>`, `i64<2>` and `u64<2>`. Numeric vectors remain at most
128 bits; pointer-sized integer vectors remain excluded. The native ABI must
retain exact lane width, count and signedness. Ordinary floating operations
carry no fast-math or contraction permission. Independent scalar oracles and
optimized packed-double disassembly cover the selected x86-64 baseline.

Runtime selection is explicit and fails closed. The initial minimal
profile is a Linux x86-64 process without libc, using a separately identified
startup and Linux syscall boundary. Target object emission and actual no-OS
execution have separate evidence requirements. Hosted compilation remains the
default. No installed SuperH target was present at intake.

ByteArena retains its checked IDs and capacity/alignment authority. Its new
typed encoded fields avoid importing native layout or pointer alignment into
byte storage. PacketArena admits two POD payloads plus exact unique Resource
owners held in compiler-managed fields. Initial backing is hosted; successful
placement allocates no packet heap block. Read results are copied typed values,
and resource extraction or escaping arena pointers are outside this profile.

Volatile operations retain the existing memory Place and immutable typed intent
through Checked/Core/CFG/SSA. The emitted operation retains exact width,
alignment and address, and hardware watchpoints independently observe the host
mapped-page sequence. Source-order effects are retained in SSA.

An ownership corruption test exposed an inherited SSA gap for omitted foreign
Resource cleanup. The builder now retains each cleanup's exact disposal edge
and once-only identity; verification checks that obligation independently of
the normal generated program's successful cleanup.

The final integration freeze and source/product receipts determine S1–S7
acceptance. Historical LAZY Q4 stays HELD/INCOMPLETE. AArch64 object emission,
missing SuperH support and unexecuted no-OS code keep separate status labels.
