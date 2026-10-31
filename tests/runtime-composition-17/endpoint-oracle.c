/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "../../lib/runtime/platform/network-posix.h"
#include <arpa/inet.h>
#include <stddef.h>
#include <string.h>

int endpoint_oracle(const AstraNetEndpoint *ipv4, const AstraNetEndpoint *ipv6) {
	unsigned char expected[16] = {0};
	if (sizeof(*ipv4) != 28 || offsetof(AstraNetEndpoint, scope) != 24) return 20;
	if (inet_pton(AF_INET, "192.0.2.2", expected) != 1 || ipv4->family != 4 || ipv4->port != 17431 || ipv4->scope || memcmp(ipv4->address, expected, 16)) return 21;
	if (inet_pton(AF_INET6, "fd17:6173:7472::2", expected) != 1 || ipv6->family != 6 || ipv6->port != 41743 || ipv6->scope || memcmp(ipv6->address, expected, 16)) return 22;
	return 0;
}
