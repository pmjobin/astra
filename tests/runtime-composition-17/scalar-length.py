#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute scalar lengths in a body requiring scoped carrier lifetime proofs."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-scalar-length')
	source = Path(__file__).with_suffix('.astra')
	api = ROOT / 'lib/bindings/memory/contexts.vapi'
	provider = ROOT / 'lib/runtime/runtime/context-17.c'
	runtime = e.output / 'context17.o'
	e.files(source, api, provider, provider.with_suffix('.h'), Path(__file__), ROOT / 'tests/systems-dsp-9/support.py')
	e.run(['cc', '-O2', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', runtime])
	for level in ['0', '1', '2']:
		product = e.output / ('length-O' + level)
		e.run([e.compiler, '-O' + level, source, '--vapi', api, '--link-object', runtime, '--link-library', 'pthread', '-o', product])
		e.run([product], stdout='', timeout=10)
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'length-O2'], stdout='', contains='ERROR SUMMARY: 0 errors')
	e.files(runtime)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
