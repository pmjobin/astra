#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual replacement preserves cell generation, original context and retirement."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-same-nominal-sync')
	here = Path(__file__).resolve().parent
	original = here / 'same-nominal-sync.astra'
	text = original.read_text()
	source = e.output / 'mutation.astra'
	source.write_text(text)
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'same-nominal-sync-oracle.c']
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	expected = 'scoped sync error: empty carrier acquires and transfers its original payload once\n'
	for level in ['O0', 'O1', 'O2']:
		obj = e.output / ('mutation-' + level + '.o')
		product = obj.with_suffix('')
		e.run([e.compiler, '-' + level, '-c', source, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, '-o', product])
		e.run([product], stdout=expected)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], stdout=expected, contains='ERROR SUMMARY: 0 errors')
	instrument(e, 'mutation', [source], providers, expected, 'address', vapis=[vapi], entry_symbol='same_sync_probe')
	for name, changed, diagnostic in [
		('moved-error', text.replace('if (error.read() != 17)', 'var lost = move error; if (error.read() != 17)'), 'moved'),
		('retired-backing', text.replace('sync_fail(move input);', 'release backing; sync_fail(move input);'), 'exclusively borrowed'),
	]:
		assert changed != text
		negative = e.output / (name + '.astra')
		negative.write_text(changed)
		e.run([e.compiler, '--check', negative, '--vapi', vapi], expected=1, contains=diagnostic)
		e.files(negative)
	e.files(original, source, Path(__file__), vapi, *providers, ROOT / 'lib/runtime/runtime/context-17.h', ROOT / 'tests/systems-dsp-9/support.py', ROOT / 'tests/concurrency-runtime-13/sanitizers.py')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
