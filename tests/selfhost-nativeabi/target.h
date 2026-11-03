// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <float.h>
#include <limits.h>
#include <stdint.h>
_Static_assert(CHAR_BIT == 8 && sizeof(int32_t) == 4 && sizeof(void *) == 8, "qualified LP64 scalar target");
_Static_assert(sizeof(float) == 4 && FLT_RADIX == 2 && FLT_MANT_DIG == 24 && FLT_MIN_EXP == -125 && FLT_MAX_EXP == 128, "qualified IEEE binary32 C channel");
_Static_assert(sizeof(double) == 8 && DBL_MANT_DIG == 53 && DBL_MIN_EXP == -1021 && DBL_MAX_EXP == 1024, "qualified IEEE binary64 C channel");
