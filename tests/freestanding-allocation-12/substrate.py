# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Strict, sanitized and unsuppressed native storage-admission probes."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'allocation-substrate')
	runtime = ROOT / 'lib/runtime/runtime'
	sources = [ROOT / 'tests/freestanding-allocation-12/allocation-runtime.c',
		runtime / 'allocation-12.c', runtime / 'allocation-12-host.c']
	expected = 'allocator substrate: region,pool,custom,heap,static; align,overflow,origin,generation,reentry: OK\n'
	for name, flags in [('strict', ['-O2']), ('sanitized', ['-O1', '-g',
		'-fsanitize=address,undefined', '-fno-omit-frame-pointer'])]:
		product = e.output / name
		e.run(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic',
			*flags, '-I' + str(runtime), *sources, '-o', product])
		e.run([product], stdout=expected, env={'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1',
			'UBSAN_OPTIONS': 'halt_on_error=1:print_stacktrace=1'})
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99',
		'--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all',
		e.output / 'strict'], stdout=expected, contains='ERROR SUMMARY: 0 errors')
	e.files(*sources, runtime / 'allocation-12.h')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
