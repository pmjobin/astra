/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_DIAGNOSTICS_H
#define ASTRA_DIAGNOSTICS_H

#include <limits.h>
#include <stdint.h>

_Static_assert(CHAR_BIT == 8 && sizeof(int32_t) == 4, "diagnostics require 8-bit bytes and signed I32");

/* Select exactly one provider. This hook never returns and does not unwind.
 * Text is an immutable bounded borrow: no retention, mutation, free, lifetime
 * invalidation or borrowed result. Null is permitted only with a zero count.
 * Counts frame the bytes; NUL is ordinary data. Pointers must remain readable.
 * The hosted provider uses stdio and abort; it is not async-signal-safe.
 */
_Noreturn void astra_diag_assert_fail_v0(const unsigned char *file, int32_t file_length, int32_t line, const unsigned char *expression, int32_t expression_length, const unsigned char *message, int32_t message_length);

#endif
