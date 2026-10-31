/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_BASE_FAILURE_H
#define ASTRA_BASE_FAILURE_H

#include <stdint.h>
#include <limits.h>

_Static_assert(sizeof(int) == 4 && INT_MAX == INT32_MAX && INT_MIN == INT32_MIN, "Astra CABI I32 requires an exact signed 32-bit C int");

/* kind 1: assertion; kind 2: invalid clamp bounds. Never return or unwind. */
_Noreturn void astra_base_fail(int32_t kind, int32_t code);

/* Hosted-only, scalar-fp-v2 channels. These also never return or unwind. */
_Noreturn void astra_base_equal_i32(int32_t code, int32_t actual, int32_t expected);
_Noreturn void astra_base_equal_f32(int32_t code, float actual, float expected);
_Noreturn void astra_base_equal_f64(int32_t code, double actual, double expected);

#endif
