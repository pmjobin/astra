# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Separate native objects preserve one named domain and storage attributes."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from owners import domain


def main(compiler, output):
	e = Evidence(compiler, output, 'allocation-modules')
	here = ROOT / 'tests/freestanding-allocation-12'
	runtime = ROOT / 'lib/runtime/runtime'
	common = e.output / 'allocation.o'
	oracle = e.output / 'unit-oracle.o'
	e.run(['clang', '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic',
		'-c', runtime / 'allocation-12.c', '-o', common])
	e.run(['clang', '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic',
		'-I' + str(runtime), '-DUNIT_DOMAIN=' + domain(1, 'unit12.region', 256, 8),
		'-c', here / 'unit-oracle.c', '-o', oracle])
	for level in (0, 1, 2):
		interface = e.output / f'unit-O{level}.asti'
		implementation = e.output / f'unit-O{level}.o'
		e.run([e.compiler, f'-O{level}', '-c', '--module', 'Alloc12',
			'--emit-interface', interface, '--native-export', 'Alloc12.Entry',
			'--native-export', 'Alloc12.Snapshot', '--native-export', 'Alloc12.create',
			here / 'unit-provider.astra', '-o', implementation])
		text = interface.read_text()
		assert '[Allocator(' in text and '[Repr(' in text and '[Align(' in text
		for consumer_level in (0, 1, 2):
			product = e.output / f'unit-p{level}-c{consumer_level}'
			e.run([e.compiler, f'-O{consumer_level}', '--import-module', interface,
				here / 'unit-consumer.astra', '--link-object', common,
				'--link-object', oracle, '-o', product])
			e.run([product], expected=42, stdout='7,8,9,-9,-8,-7,\n')
			e.files(product)
		e.files(interface, implementation)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99',
		'--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all',
		e.output / 'unit-p2-c2'], expected=42, contains='ERROR SUMMARY: 0 errors')
	e.files(here / 'unit-provider.astra', here / 'unit-consumer.astra', here / 'unit-oracle.c', common, oracle)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
