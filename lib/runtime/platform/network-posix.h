/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_NETWORK_POSIX_H
#define ASTRA_NETWORK_POSIX_H
#include <stdint.h>

/* Numeric endpoint/1. Address bytes are network ordered. Port and scope are
 * host ordered. The Astra POD spells the 16 byte address as four opaque u32s. */
typedef struct AstraNetEndpoint {
	int32_t family;
	uint8_t address[16];
	int32_t port;
	uint32_t scope;
} AstraNetEndpoint;
typedef struct AstraNetPacket {
	AstraNetEndpoint peer;
	int32_t message_length;
} AstraNetPacket;

int32_t astra_net_endpoint_parse(const uint8_t *, int32_t, int32_t, int32_t,
                                 int32_t, AstraNetEndpoint *);
int32_t astra_net_endpoint_format(const AstraNetEndpoint *, uint8_t *, int32_t);
int32_t astra_net_socket_family(int32_t, int32_t);
int32_t astra_net_bind_at(int32_t, const AstraNetEndpoint *);
int32_t astra_net_connect_to(int32_t, const AstraNetEndpoint *);
int32_t astra_net_address(int32_t, int32_t, AstraNetEndpoint *);
int32_t astra_net_accept_from(int32_t, AstraNetEndpoint *);
int32_t astra_net_send_to(int32_t, const AstraNetEndpoint *, uint8_t *, int32_t,
                          int32_t, int32_t);
int32_t astra_net_receive_from(int32_t, uint8_t *, int32_t, int32_t, int32_t,
                               AstraNetPacket *);
#endif
