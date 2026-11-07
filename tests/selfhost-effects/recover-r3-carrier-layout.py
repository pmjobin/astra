#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent GCC/Clang offsets for mixed floating carriers."""
from state import ROOT, load_module

FIELDS = r'''typedef struct Floating { float narrow; int32_t integer; double wide; } Floating;
typedef struct FloatingBuffer { double *data; int32_t count; } FloatingBuffer;
_Static_assert(sizeof(float) == 4 && _Alignof(float) == 4, "f32");
_Static_assert(sizeof(double) == 8 && _Alignof(double) == 8, "f64");
_Static_assert(sizeof(Floating) == 16 && _Alignof(Floating) == 8 && offsetof(Floating, narrow) == 0 && offsetof(Floating, integer) == 4 && offsetof(Floating, wide) == 8, "mixed floating record");
_Static_assert(sizeof(FloatingBuffer) == 16 && _Alignof(FloatingBuffer) == 8 && offsetof(FloatingBuffer, data) == 0 && offsetof(FloatingBuffer, count) == 8, "floating buffer");
'''


def main():
	runner = load_module('r3_floating_layout_runner', ROOT/'tests/selfhost-effects/recover-layout.py')
	runner.SOURCE = runner.SOURCE.replace('typedef struct Descriptor Descriptor;', FIELDS+'\ntypedef struct Descriptor Descriptor;')
	runner.main()


if __name__ == '__main__':
	main()
