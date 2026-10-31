/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Parent traces only its own child with four x86 hardware data watchpoints. */
#include <assert.h>
#include <errno.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ptrace.h>
#include <sys/user.h>
#include <sys/wait.h>
#include <unistd.h>

static uintptr_t debug_offset(int index) {
	return offsetof(struct user, u_debugreg) + (uintptr_t)index * sizeof(unsigned long);
}
static void debug(pid_t child, int index, uintptr_t value) {
	assert(ptrace(PTRACE_POKEUSER, child, (void *)debug_offset(index), (void *)value) == 0);
}
static unsigned long peek(pid_t child, enum __ptrace_request request, uintptr_t address) {
	errno = 0;
	long result = ptrace(request, child, (void *)address, NULL);
	assert(result != -1 || errno == 0);
	return (unsigned long)result;
}
int main(int argc, char **argv) {
	assert(argc == 2);
	int channel[2];
	assert(pipe(channel) == 0);
	pid_t child = fork();
	assert(child >= 0);
	if (!child) {
		close(channel[0]);
		char descriptor[32];
		snprintf(descriptor, sizeof descriptor, "%d", channel[1]);
		assert(setenv("ASTRA_WATCH_FD", descriptor, 1) == 0);
		assert(ptrace(PTRACE_TRACEME, 0, NULL, NULL) == 0);
		execl(argv[1], argv[1], NULL);
		_exit(127);
	}
	close(channel[1]);
	int status;
	assert(waitpid(child, &status, 0) == child && WIFSTOPPED(status) && WSTOPSIG(status) == SIGTRAP);
	assert(ptrace(PTRACE_CONT, child, NULL, NULL) == 0);
	assert(waitpid(child, &status, 0) == child && WIFSTOPPED(status) && WSTOPSIG(status) == SIGSTOP);
	uintptr_t addresses[4];
	assert(read(channel[0], addresses, sizeof addresses) == (ssize_t)sizeof addresses);
	close(channel[0]);
	uintptr_t control = 0;
	for (int i = 0; i < 4; i++) {
		debug(child, i, addresses[i]);
		control |= (uintptr_t)1 << (2 * i);
		control |= (uintptr_t)(3 | ((i < 2 ? 3 : 2) << 2)) << (16 + 4 * i);
	}
	debug(child, 6, 0);
	debug(child, 7, control);
	static const int slots[] = {0, 0, 0, 1, 1, 2, 2, 3, 3};
	static const uint64_t values[] = {1, 2, 2, 7, 7, UINT64_C(4294967297), UINT64_C(4294967297), UINT64_C(4294967299), UINT64_C(4294967299)};
	int count = 0;
	for (;;) {
		assert(ptrace(PTRACE_CONT, child, NULL, NULL) == 0);
		assert(waitpid(child, &status, 0) == child && WIFSTOPPED(status));
		if (WSTOPSIG(status) == SIGSTOP) {
			break;
		}
		assert(WSTOPSIG(status) == SIGTRAP && count < 9);
		unsigned long hit = peek(child, PTRACE_PEEKUSER, debug_offset(6)) & 15;
		assert(hit == (1UL << slots[count]));
		uint64_t value = peek(child, PTRACE_PEEKDATA, addresses[slots[count]]);
		if (slots[count] < 2) {
			value &= UINT32_MAX;
		}
		assert(value == values[count]);
		count++;
		debug(child, 6, 0);
	}
	assert(count == 9);
	debug(child, 7, 0);
	assert(ptrace(PTRACE_CONT, child, NULL, NULL) == 0);
	assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
	puts("volatile:9 mapped accesses;exact address,width,value,order");
	return 0;
}
