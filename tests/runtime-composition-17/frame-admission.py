#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""C supplement for checked frame storage; public Astra qualification is separate."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-frame-admission-substrate')
	sources = [Path(__file__).with_suffix('.c'), ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/runtime/context-17.c']
	expected = 'frame admission substrate: unpublished refusal, header OOM, exact leases, recovery and joined virtual/worker execution\n'
	expected += 'scoped frame substrate: caller-backed region/pool frames, live-drop refusal, reuse, joined virtual execution and worker refusal\n'
	flags = ['-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-fno-builtin-calloc', '-Wl,--wrap=calloc']
	for profile in ['ordinary', 'address', 'thread']:
		product = e.output / profile
		sanitizer = [] if profile == 'ordinary' else ['-fsanitize=' + ('address,undefined' if profile == 'address' else 'thread')]
		e.run(['clang', *flags, *sanitizer, *sources, '-o', product])
		e.run([product], stdout=expected, timeout=30, env={'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1', 'UBSAN_OPTIONS': 'halt_on_error=1', 'TSAN_OPTIONS': 'halt_on_error=1'})
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'ordinary'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	e.files(*sources, Path(__file__), ROOT / 'lib/runtime/async/task-core17.c', ROOT / 'lib/runtime/async/task-api17.c', ROOT / 'lib/runtime/async/worker17.c', ROOT / 'lib/runtime/async/virtual.h', ROOT / 'lib/runtime/runtime/context-17.h')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
