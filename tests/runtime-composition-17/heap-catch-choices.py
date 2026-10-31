#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual typed catch merges retain the selected original context and owner."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-heap-catch-choices')
	here = Path(__file__).resolve().parent
	sources = [here / 'heap-catch-choices.astra']
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'heap-catch-choices-oracle.c']
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	expected = 'heap choices: selected catch origin retained, other input retired, four exact destructions\n'
	for level in ['O0', 'O1', 'O2']:
		obj = e.output / ('choices-' + level + '.o')
		product = obj.with_suffix('')
		e.run([e.compiler, '-' + level, '-c', *sources, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, '-o', product])
		e.run([product], stdout=expected)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], stdout=expected, contains='ERROR SUMMARY: 0 errors')
	instrument(e, 'choices', sources, providers, expected, 'address', vapis=[vapi], entry_symbol='heap_choice_probe')
	text = sources[0].read_text()
	for name, changed, diagnostic in [
		('moved-error', text.replace('heap_choice_observed(mode, error.read());', 'var duplicate = move error; heap_choice_observed(mode, error.read());'), 'moved'),
		('retired-backing', text.replace('\ttry {', '\trelease left_backing; try {'), 'exclusively borrowed'),
	]:
		assert changed != text
		negative = e.output / (name + '.astra')
		negative.write_text(changed)
		e.run([e.compiler, '--check', negative, '--vapi', vapi], expected=1, contains=diagnostic)
		e.files(negative)
	e.files(Path(__file__), vapi, *sources, *providers, ROOT / 'tests/systems-dsp-9/support.py', ROOT / 'tests/concurrency-runtime-13/sanitizers.py', ROOT / 'lib/runtime/runtime/context-17.h')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
