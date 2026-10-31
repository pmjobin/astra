// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Explicit opaque GNU Linux provider owner. No fd or buffer pointer escapes.
[CCode (destroy_function = "astra_linux_payload_close")]
handle LinuxPayload;
[CCode (text_abi = "utf8-i32")]
owned LinuxPayload astra_linux_payload_open(borrowed string path, int capacity, int writing);
int astra_linux_payload_configure(borrowed LinuxPayload payload, int offset, int count, i64 file_offset);
int astra_linux_payload_byte(borrowed LinuxPayload payload, int index);
int astra_linux_payload_set(borrowed LinuxPayload payload, int index, int byte);
int astra_linux_payload_count(borrowed LinuxPayload payload);
int astra_linux_payload_error(borrowed LinuxPayload payload);
int astra_linux_payload_finish(borrowed LinuxPayload payload);
