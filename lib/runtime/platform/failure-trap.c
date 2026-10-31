/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#include "failure.h"

/* Qualified as an object and a libc-free linked witness, not by builtin name. */
#if !defined(__x86_64__) || !defined(__linux__) || !defined(__GNUC__) || defined(__clang__)
#error "Astra base trap provider is only qualified for GCC x86-64 Linux"
#endif

_Noreturn void astra_base_fail(int32_t kind, int32_t code) {
	(void)kind;
	(void)code;
	__builtin_trap();
}
