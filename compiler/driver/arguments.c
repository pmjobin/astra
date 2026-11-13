// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// GNU/Linux ELF argument transport only. The Astra driver owns option parsing,
// file loading, diagnostics and every compiler phase. No compiler delegation.
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <limits.h>

#if !defined(__linux__) || !defined(__x86_64__) || defined(__ILP32__)
#error "astrac argument transport is qualified for GNU/Linux x86-64 LP64"
#endif

static int argument_count;
static char **argument_values;

// glibc passes the process arguments to ELF init-array functions. Borrowed OS
// storage remains valid until exit; Astra immediately makes checked UTF-8 copies.
__attribute__((constructor)) static void capture_arguments(int argc, char **argv, char **envp) {
	(void)envp;
	if (argc > 0 && argv && !argv[argc]) {
		argument_count = argc;
		argument_values = argv;
	}
}

int32_t astrac_argument_count(void) {
	return argument_count;
}

int32_t astrac_argument_length(int32_t index) {
	if (index < 0 || index >= argument_count || !argument_values[index]) return -1;
	size_t length = strlen(argument_values[index]);
	return length <= INT32_MAX ? (int32_t)length : -1;
}

int32_t astrac_argument_byte(int32_t index, int32_t offset) {
	int32_t length = astrac_argument_length(index);
	if (offset < 0 || offset >= length) return -1;
	return (unsigned char)argument_values[index][offset];
}
