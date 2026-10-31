#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Allocator substrate controls; does not establish emitted owner/frame placement."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-context-substrate')
	here = Path(__file__).resolve().parent
	provider = ROOT / 'lib/runtime/runtime/context-17.c'
	sources = [here / 'context-tests.c', here / 'context-provider.c', provider]
	expected = 'context substrate: distinct instances, backing leases, external provider, checked failures, generations, reentry and 804 concurrent allocations\n'
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('contexts-' + level)
		e.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-g', '-' + level, *sources, '-o', product])
		e.run([product], stdout=expected, timeout=15)
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'contexts-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	product = e.output / 'contexts-address'
	e.run(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-g', '-O1', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', *sources, '-o', product])
	e.run([product], stdout=expected, timeout=20, env={'ASAN_OPTIONS': 'detect_leaks=1:abort_on_error=1', 'UBSAN_OPTIONS': 'halt_on_error=1'})
	e.files(product, *sources, provider.with_suffix('.h'), here / 'context-provider.h', Path(__file__))
	product = e.output / 'contexts-thread'
	e.run(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-g', '-O1', '-fsanitize=thread', *sources, '-o', product])
	e.run([product], stdout=expected, timeout=20, env={'TSAN_OPTIONS': 'halt_on_error=1'})
	e.files(product)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
