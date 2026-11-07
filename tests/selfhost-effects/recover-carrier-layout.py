#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Add independent C/C++ carrier layout assertions to the root witness."""
from state import ROOT, load_module

FIELDS = r'''#include <stdbool.h>
typedef struct Pair { int32_t left, right; } Pair;
typedef struct Mixed { bool tag; int16_t middle; int64_t wide; } Mixed;
typedef struct Buffer { int32_t *data; int32_t count; } Buffer;
typedef struct ClassCarrier { void *value; } ClassCarrier;
_Static_assert(sizeof(Pair) == 8 && _Alignof(Pair) == 4 && offsetof(Pair, left) == 0 && offsetof(Pair, right) == 4, "copyable record");
_Static_assert(sizeof(Mixed) == 16 && _Alignof(Mixed) == 8 && offsetof(Mixed, tag) == 0 && offsetof(Mixed, middle) == 2 && offsetof(Mixed, wide) == 8, "mixed scalar record alignment");
_Static_assert(sizeof(Buffer) == 16 && _Alignof(Buffer) == 8 && offsetof(Buffer, data) == 0 && offsetof(Buffer, count) == 8, "owned buffer carrier");
_Static_assert(sizeof(ClassCarrier) == 8 && _Alignof(ClassCarrier) == 8 && offsetof(ClassCarrier, value) == 0, "Class pointer carrier");
'''


if __name__ == '__main__':
	runner = load_module('carrier_layout_runner', ROOT/'tests/selfhost-effects/recover-layout.py')
	runner.SOURCE = runner.SOURCE.replace('typedef struct Descriptor Descriptor;', FIELDS+'\ntypedef struct Descriptor Descriptor;')
	runner.main()
