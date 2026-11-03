// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <assert.h>
#include <stdint.h>
static int completed_phase_sockets;
int32_t __real_net_oracle_lifetimes(int32_t expected);

int32_t __wrap_net_oracle_lifetimes(int32_t phase_sockets) {
	assert((completed_phase_sockets == 0 && phase_sockets == 12) ||
	       (completed_phase_sockets == 12 && phase_sockets == 3));
	return __real_net_oracle_lifetimes(completed_phase_sockets + phase_sockets);
}

int32_t app_network_udp_phase(void) {
	assert(completed_phase_sockets == 0);
	__real_net_oracle_lifetimes(12);
	completed_phase_sockets = 12;
	return 0;
}
