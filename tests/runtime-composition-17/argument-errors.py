#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute named-owner reservation abort and successful call entry."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-argument-errors')
	source = Path(__file__).with_suffix('.astra')
	e.files(source, Path(__file__), ROOT / 'tests/systems-dsp-9/support.py')
	for level in ['0', '1', '2']:
		product = e.output / ('arguments-O' + level)
		e.run([e.compiler, '-O' + level, source, '-o', product])
		e.run([product], stdout='', timeout=10)
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'arguments-O2'], stdout='', contains='ERROR SUMMARY: 0 errors')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
