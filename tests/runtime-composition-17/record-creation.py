#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute record creation from heap owners alongside a scoped allocator."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-record-creation')
	here = Path(__file__).resolve().parent
	source = here / 'record-creation.astra'
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'record-creation-oracle.c']
	e.files(source, vapi, *providers, Path(__file__))
	flags = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		flags += ['--link-object', obj]
		e.files(obj)
	expected = 'record creation: promoted flat/nested/generic fields, checked factories and local moves, scoped context calls, 6 observed exceptions and 30 exact retirements\n'
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('record-creation-' + level)
		e.run([e.compiler, '-' + level, source, '--vapi', vapi, *flags, '--link-library', 'pthread', '-o', product])
		e.run([product], stdout=expected, timeout=15)
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'record-creation-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
