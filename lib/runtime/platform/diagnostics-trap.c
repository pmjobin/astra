/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "diagnostics.h"

/* The emitted GCC/Clang objects and libc-free witness qualify this target. */
#if !defined(__x86_64__) || !defined(__linux__) || (!defined(__GNUC__) && !defined(__clang__))
#error "Astra diagnostic trap provider requires qualified GCC/Clang x86-64 Linux"
#endif

_Noreturn void astra_diag_assert_fail_v0(const unsigned char *file, int32_t file_length, int32_t line, const unsigned char *expression, int32_t expression_length, const unsigned char *message, int32_t message_length) {
	(void)file;
	(void)file_length;
	(void)line;
	(void)expression;
	(void)expression_length;
	(void)message;
	(void)message_length;
	__builtin_trap();
}
