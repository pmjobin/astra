// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Selected resource-admission boundary for the bounded typed packet arena.
[CCode(destroy_function = "astra_packet_resource_close")]
handle PacketResource;
