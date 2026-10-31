/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include <stdlib.h>
#include <errno.h>

/* Test launch configuration only; all client protocol logic is emitted Astra. */
int endpoint_test_port(int datagram) {
	const char *value = getenv(datagram ? "M17_UDP_PORT" : "M17_TCP_PORT");
	if (!value || !*value) return -1;
	errno = 0;
	char *end = NULL;
	long port = strtol(value, &end, 10);
	return errno || *end || port < 1024 || port > 65535 ? -1 : (int)port;
}
