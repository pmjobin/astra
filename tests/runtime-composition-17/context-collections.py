#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Selected container backing, growth rollback and real closure placement."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-context-collections')
	provider = ROOT / 'lib/runtime/runtime/context-17.c'
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	sources = [Path(__file__).with_suffix('.astra'), ROOT / 'lib/astra/collections/context-bag.astra']
	obj = e.output / 'context-17.o'
	e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('collections-' + level)
		e.run([e.compiler, '-' + level, *sources, '--vapi', vapi, '--link-object', obj, '--link-library', 'pthread', '-o', product])
		e.run([product], stdout='', timeout=15)
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'collections-O2'], stdout='', contains='ERROR SUMMARY: 0 errors', timeout=45)
	for sanitizer in ['address', 'thread']:
		instrument(e, 'collections', sources, [provider], '', sanitizer, vapis=[vapi])
	e.files(*sources, provider, provider.with_suffix('.h'), vapi, obj, Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
